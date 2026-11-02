import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { PublicClientApplication, EventType, AuthenticationResult } from "@azure/msal-browser";
import { MsalProvider } from "@azure/msal-react";
import { msalConfig } from "./authConfig";
import App from "./App";

const msalInstance = new PublicClientApplication(msalConfig);

await msalInstance.initialize();
await msalInstance.handleRedirectPromise();

const accounts = msalInstance.getAllAccounts();
if (accounts.length > 0 && !msalInstance.getActiveAccount()) {
  msalInstance.setActiveAccount(accounts[0]);
}
msalInstance.addEventCallback((e) => {
  if (e.eventType === EventType.LOGIN_SUCCESS && e.payload) {
    msalInstance.setActiveAccount((e.payload as AuthenticationResult).account);
  }
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <MsalProvider instance={msalInstance}>
      <App />
    </MsalProvider>
  </StrictMode>
);
