import { Injectable, InjectionToken, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, tap } from 'rxjs';

export interface AuthConfig { cognitoRegion: string; userPoolId: string; clientId: string; }
export const AUTH_CONFIG = new InjectionToken<AuthConfig>('AUTH_CONFIG');

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  private config = inject(AUTH_CONFIG);
  get enabled(): boolean { return !!(this.config.userPoolId && this.config.clientId && this.config.cognitoRegion); }
  get authenticated(): boolean { return !!sessionStorage.getItem('chat-id-token'); }

  signUp(email: string, password: string): Observable<unknown> {
    return this.cognito('SignUp', {
      ClientId: this.config.clientId, Username: email, Password: password,
      UserAttributes: [{ Name: 'email', Value: email }]
    });
  }

  signIn(email: string, password: string): Observable<unknown> {
    return this.cognito('InitiateAuth', {
      AuthFlow: 'USER_PASSWORD_AUTH', ClientId: this.config.clientId,
      AuthParameters: { USERNAME: email, PASSWORD: password }
    }).pipe(tap((result: any) => {
      const token = result?.AuthenticationResult?.IdToken;
      if (!token) throw new Error('Cognito nie zwróciło tokenu logowania.');
      sessionStorage.setItem('chat-id-token', token);
    }));
  }

  signOut(): void { sessionStorage.removeItem('chat-id-token'); }

  private cognito(operation: string, body: object): Observable<any> {
    const endpoint = `https://cognito-idp.${this.config.cognitoRegion}.amazonaws.com/`;
    const headers = new HttpHeaders({
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': `AWSCognitoIdentityProviderService.${operation}`
    });
    return this.http.post(endpoint, body, { headers });
  }
}
