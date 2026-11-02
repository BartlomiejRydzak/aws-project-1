import { Injectable, InjectionToken, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

export const API_URL = new InjectionToken<string>('API_URL');

export interface FileInfo { id: string; name: string; contentType: string; size: number; }
export interface User { username: string; joinedAt: string; }
export interface Message { id: number; author: string; text: string; file: FileInfo | null; timestamp: string; }

@Injectable({ providedIn: 'root' })
export class ChatService {
  private http = inject(HttpClient);
  private api = inject(API_URL);

  getMessages(after = 0): Observable<Message[]> {
    return this.http.get<Message[]>(`${this.api}/messages`, { params: { after } });
  }
  getUsers(): Observable<User[]> {
    return this.http.get<User[]>(`${this.api}/users`);
  }
  getMe(): Observable<User> {
    return this.http.get<User>(`${this.api}/users/me`);
  }
  join(username: string): Observable<User> {
    return this.http.post<User>(`${this.api}/users`, { username });
  }
  send(author: string, text: string, fileId: string | null): Observable<Message> {
    return this.http.post<Message>(`${this.api}/messages`, { author, text, fileId });
  }
  upload(file: File): Observable<FileInfo> {
    const form = new FormData();
    form.append('file', file);
    return this.http.post<FileInfo>(`${this.api}/files`, form);
  }
  downloadFile(id: string): Observable<Blob> {
    return this.http.get(`${this.api}/files/${id}`, { responseType: 'blob' });
  }
}
