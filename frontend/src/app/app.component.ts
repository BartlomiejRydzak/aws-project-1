import { Component, ElementRef, OnDestroy, OnInit, ViewChild, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpErrorResponse } from '@angular/common/http';
import { ChatService, FileInfo, Message, User } from './chat.service';
import { AuthService } from './auth.service';
import { Subscription, interval } from 'rxjs';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
  @if (auth.enabled && !auth.authenticated) {
    <main class="join">
      <h1>Pokój</h1>
      <p>{{ authMode === 'signup' ? 'Utwórz konto, aby wejść do czatu.' : 'Zaloguj się przez Amazon Cognito.' }}</p>
      <form (ngSubmit)="authenticate()">
        <input name="email" type="email" [(ngModel)]="email" placeholder="Adres e-mail" autocomplete="email" required>
        <input name="password" type="password" [(ngModel)]="password" placeholder="Hasło" autocomplete="current-password" required>
        <button type="submit" [disabled]="busy">{{ authMode === 'signup' ? 'Utwórz konto' : 'Zaloguj się' }}</button>
      </form>
      <button type="button" class="auth-switch" (click)="authMode = authMode === 'signin' ? 'signup' : 'signin'">
        {{ authMode === 'signin' ? 'Nie masz konta? Zarejestruj się' : 'Masz już konto? Zaloguj się' }}
      </button>
      @if (error) { <p class="error" role="alert">{{ error }}</p> }
    </main>
  } @else if (!me) {
    <main class="join">
      <h1>Pokój</h1>
      <p>Wspólny czat dla wszystkich, którzy są teraz online. Wybierz nazwę i wejdź.</p>
      <form (ngSubmit)="join()">
        <input name="u" [(ngModel)]="nameInput" maxlength="24" placeholder="Twoja nazwa" autocomplete="off" required>
        <button type="submit" [disabled]="!nameInput.trim()">Wejdź do pokoju</button>
      </form>
      @if (auth.enabled) { <button class="auth-switch" type="button" (click)="logout()">Wyloguj</button> }
      @if (error) { <p class="error" role="alert">{{ error }}</p> }
    </main>
  } @else {
    <div class="layout">
      <aside>
        <h2>W pokoju ({{ users.length }})</h2>
        <ul>
          @for (u of users; track u.username) {
            <li [class.me]="u.username === me">{{ u.username }}</li>
          }
        </ul>
      </aside>

      <section class="chat">
        @if (auth.enabled) {
          <div class="chat-header">
            <span>Zalogowano jako <strong>{{ me }}</strong></span>
            <button class="logout-button" type="button" (click)="logout()">Wyloguj się</button>
          </div>
        }
        <div class="messages" #scroller>
          @if (messages.length === 0) {
            <p class="empty">Nikt jeszcze nic nie napisał. Zacznij rozmowę.</p>
          }
          @for (m of messages; track m.id) {
            <article [class.mine]="m.author === me">
              <header>
                <strong>{{ m.author }}</strong>
                <time>{{ m.timestamp | date:'HH:mm' }}</time>
              </header>
              @if (m.text) { <p>{{ m.text }}</p> }
              @if (m.file; as f) {
                @if (f.contentType.startsWith('image/')) {
                  <img [src]="mediaUrl(f)" [alt]="f.name">
                } @else if (f.contentType.startsWith('video/')) {
                  <video [src]="mediaUrl(f)" controls></video>
                } @else {
                  <audio [src]="mediaUrl(f)" controls></audio>
                }
                <a class="fname" [href]="mediaUrl(f)" [download]="f.name">{{ f.name }}</a>
              }
            </article>
          }
        </div>

        @if (error) { <p class="error" role="alert">{{ error }}</p> }

        <form class="composer" (ngSubmit)="send()">
          <label class="attach" title="Dołącz obraz, wideo lub audio">
            Załącznik
            <input type="file" accept="image/*,video/*,audio/*" (change)="pick($event)" hidden>
          </label>
          @if (pending) {
            <span class="chip">{{ pending.name }} <button type="button" (click)="pending = null" aria-label="Usuń załącznik">×</button></span>
          }
          <input name="t" [(ngModel)]="text" maxlength="2000" placeholder="Napisz wiadomość" autocomplete="off">
          <button type="submit" [disabled]="busy || (!text.trim() && !pending)">Wyślij</button>
        </form>
      </section>
    </div>
  }
  `
})
export class AppComponent implements OnInit, OnDestroy {
  private svc = inject(ChatService);
  auth = inject(AuthService);
  @ViewChild('scroller') scroller?: ElementRef<HTMLDivElement>;

  me = '';
  nameInput = '';
  email = '';
  password = '';
  authMode: 'signin' | 'signup' = 'signin';
  text = '';
  error = '';
  busy = false;
  messages: Message[] = [];
  users: User[] = [];
  pending: File | null = null;
  mediaUrls: Record<string, string> = {};
  private poll?: Subscription;

  ngOnInit(): void {
    if (this.auth.enabled && this.auth.authenticated) this.restoreChatUser();
  }

  join(): void {
    this.error = '';
    this.svc.join(this.nameInput.trim()).subscribe({
      next: u => { this.me = u.username; this.nameInput = u.username; this.startPolling(); },
      error: e => this.error = this.msg(e)
    });
  }

  private restoreChatUser(): void {
    this.svc.getMe().subscribe({
      next: u => { this.me = u.username; this.nameInput = u.username; this.startPolling(); },
      error: e => {
        if (e instanceof HttpErrorResponse && e.status === 404) return;
        this.error = this.msg(e);
      }
    });
  }

  authenticate(): void {
    this.error = '';
    this.busy = true;
    const onFailure = (e: unknown) => { this.error = this.msg(e); this.busy = false; };
    const onSignedIn = () => {
      this.error = '';
      this.busy = false;
      this.restoreChatUser();
    };

    if (this.authMode === 'signup') {
      this.auth.signUp(this.email.trim(), this.password).subscribe({
        next: () => this.auth.signIn(this.email.trim(), this.password).subscribe({
          next: onSignedIn,
          error: onFailure
        }),
        error: onFailure
      });
      return;
    }

    this.auth.signIn(this.email.trim(), this.password).subscribe({ next: onSignedIn, error: onFailure });
  }

  logout(): void {
    this.auth.signOut();
    this.password = '';
    this.poll?.unsubscribe();
    this.poll = undefined;
    this.me = '';
    this.messages = [];
    this.users = [];
    Object.values(this.mediaUrls).forEach(url => URL.revokeObjectURL(url));
    this.mediaUrls = {};
  }

  pick(ev: Event): void {
    const input = ev.target as HTMLInputElement;
    this.pending = input.files?.[0] ?? null;
    input.value = '';
  }

  send(): void {
    if (this.busy) return;
    this.busy = true;
    this.error = '';
    const finish = (fileId: string | null) =>
      this.svc.send(this.me, this.text, fileId).subscribe({
        next: () => { this.text = ''; this.pending = null; this.busy = false; this.refresh(); },
        error: e => { this.error = this.msg(e); this.busy = false; }
      });

    if (this.pending) {
      this.svc.upload(this.pending).subscribe({
        next: (f: FileInfo) => finish(f.id),
        error: e => { this.error = this.msg(e); this.busy = false; }
      });
    } else {
      finish(null);
    }
  }

  mediaUrl(f: FileInfo): string { return this.mediaUrls[f.id] ?? ''; }

  private startPolling(): void {
    this.refresh();
    this.poll = interval(2000).subscribe(() => this.refresh());
  }

  private refresh(): void {
    const last = this.messages.length ? this.messages[this.messages.length - 1].id : 0;
    this.svc.getMessages(last).subscribe({
      next: fresh => {
        if (fresh.length) {
          this.messages = [...this.messages, ...fresh];
          fresh.forEach(message => {
            if (message.file && !this.mediaUrls[message.file.id]) {
              this.svc.downloadFile(message.file.id).subscribe({
                next: blob => this.mediaUrls[message.file!.id] = URL.createObjectURL(blob),
                error: () => {}
              });
            }
          });
          setTimeout(() => this.scroller && (this.scroller.nativeElement.scrollTop = this.scroller.nativeElement.scrollHeight));
        }
      },
      error: () => this.error = 'Brak połączenia z serwerem.'
    });
    this.svc.getUsers().subscribe({ next: u => this.users = u, error: () => {} });
  }

  private msg(e: unknown): string {
    if (e instanceof HttpErrorResponse) {
      return e.error?.message ?? (e.status === 0 ? 'Brak połączenia z serwerem.' : 'Wystąpił błąd.');
    }
    return 'Wystąpił błąd.';
  }

  ngOnDestroy(): void {
    this.poll?.unsubscribe();
    Object.values(this.mediaUrls).forEach(url => URL.revokeObjectURL(url));
  }
}
