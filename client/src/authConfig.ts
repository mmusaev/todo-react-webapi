import { Configuration } from "@azure/msal-browser";

export const msalConfig: Configuration = {
  auth: {
    clientId: import.meta.env.VITE_CLIENT_ID,
    authority: `https://login.microsoftonline.com/${import.meta.env.VITE_TENANT_ID}`,
    redirectUri: window.location.origin,
  },
  cache: { cacheLocation: "sessionStorage" },
};

export const apiScopes = [`api://${import.meta.env.VITE_API_CLIENT_ID}/access_as_user`];
export const apiUrl: string = import.meta.env.VITE_API_URL;
