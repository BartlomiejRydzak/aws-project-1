import { bootstrapApplication } from '@angular/platform-browser';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { AppComponent } from './app/app.component';
import { API_URL } from './app/chat.service';
import { AUTH_CONFIG } from './app/auth.service';

// Adres backendu jest wczytywany w czasie działania (assets/config.json),
// dzięki czemu ten sam obraz Dockera można uruchomić z dowolnym backendem.
fetch('assets/config.json')
  .then(r => r.json())
  .catch(() => ({ apiUrl: 'http://localhost:8080/api', cognitoRegion: '', userPoolId: '', clientId: '' }))
  .then(cfg =>
    bootstrapApplication(AppComponent, {
      providers: [
        provideHttpClient(withInterceptors([(req, next) => {
          const token = sessionStorage.getItem('chat-id-token');
          return next(token ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }) : req);
        }])),
        { provide: API_URL, useValue: cfg.apiUrl },
        { provide: AUTH_CONFIG, useValue: cfg }
      ]
    })
  )
  .catch(err => console.error(err));
