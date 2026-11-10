const CSRF_KEY = "open5g.csrf";

export function readCsrf(): string | null {
  if (typeof sessionStorage === "undefined") {
    return null;
  }
  return sessionStorage.getItem(CSRF_KEY);
}

export function writeCsrf(token: string): void {
  sessionStorage.setItem(CSRF_KEY, token);
}

export function clearCsrf(): void {
  sessionStorage.removeItem(CSRF_KEY);
}
