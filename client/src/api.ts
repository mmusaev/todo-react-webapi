import { IPublicClientApplication, InteractionRequiredAuthError } from "@azure/msal-browser";
import { apiScopes, apiUrl } from "./authConfig";

export interface Todo {
  id: string;
  title: string;
  isDone: boolean;
}

export async function getToken(msal: IPublicClientApplication): Promise<string> {
  const account = msal.getActiveAccount() ?? msal.getAllAccounts()[0];
  try {
    return (await msal.acquireTokenSilent({ scopes: apiScopes, account })).accessToken;
  } catch (e) {
    if (e instanceof InteractionRequiredAuthError) {
      await msal.acquireTokenRedirect({ scopes: apiScopes, account });
    }
    throw e;
  }
}

export function rolesFromToken(token: string): string[] {
  const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
  return payload.roles ?? [];
}

export async function call<T>(token: string, path: string, method = "GET", body?: unknown): Promise<T> {
  const res = await fetch(`${apiUrl}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.status === 204 ? (undefined as T) : res.json();
}
