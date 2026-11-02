import { useCallback, useEffect, useState } from "react";
import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from "@azure/msal-react";
import { apiScopes } from "./authConfig";
import { Todo, Permissions, call, getToken } from "./api";

function Todos() {
  const { instance, accounts } = useMsal();
  const [token, setToken] = useState<string>();
  const [todos, setTodos] = useState<Todo[]>([]);
  const [title, setTitle] = useState("");
  const [editing, setEditing] = useState<Todo>();
  const [error, setError] = useState<string>();
  const [perms, setPerms] = useState<Permissions>({ roles: [], permissions: [] });

  const roles = perms.roles;
  const canWrite = perms.permissions.includes("todos:write");

  const load = useCallback(async (t: string) => {
    try {
      setTodos(await call<Todo[]>(t, "/api/todos"));
      setError(undefined);
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  useEffect(() => {
    getToken(instance).then((t) => {
      setToken(t);
      call<Permissions>(t, "/api/permissions").then(setPerms).catch((e) => setError(String(e)));
      load(t);
    }).catch((e) => setError(String(e)));
  }, [instance, load]);

  const run = async (fn: () => Promise<unknown>) => {
    if (!token) return;
    try {
      await fn();
      await load(token);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const add = () => run(async () => {
    await call(token!, "/api/todos", "POST", { title, isDone: false });
    setTitle("");
  });
  const save = () => run(async () => {
    await call(token!, `/api/todos/${editing!.id}`, "PUT", { title: editing!.title, isDone: editing!.isDone });
    setEditing(undefined);
  });
  const toggle = (t: Todo) => run(() => call(token!, `/api/todos/${t.id}`, "PUT", { title: t.title, isDone: !t.isDone }));
  const remove = (t: Todo) => run(() => call(token!, `/api/todos/${t.id}`, "DELETE"));

  return (
    <>
      <p>
        {accounts[0]?.name} - role: <b>{roles.join(", ") || "none"}</b>{" "}
        <button onClick={() => instance.logoutRedirect()}>Sign out</button>
      </p>
      {error && <p style={{ color: "crimson" }}>{error}</p>}
      {canWrite && (
        <p>
          <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="New todo" />{" "}
          <button disabled={!title.trim()} onClick={add}>Add</button>
        </p>
      )}
      <ul>
        {todos.map((t) => (
          <li key={t.id}>
            {editing?.id === t.id ? (
              <>
                <input value={editing.title} onChange={(e) => setEditing({ ...editing, title: e.target.value })} />{" "}
                <button onClick={save}>Save</button> <button onClick={() => setEditing(undefined)}>Cancel</button>
              </>
            ) : (
              <>
                <input type="checkbox" checked={t.isDone} disabled={!canWrite} onChange={() => toggle(t)} />{" "}
                <span style={{ textDecoration: t.isDone ? "line-through" : "none" }}>{t.title}</span>{" "}
                {canWrite && (
                  <>
                    <button onClick={() => setEditing(t)}>Edit</button> <button onClick={() => remove(t)}>Delete</button>
                  </>
                )}
              </>
            )}
          </li>
        ))}
      </ul>
    </>
  );
}

export default function App() {
  const { instance } = useMsal();
  return (
    <div style={{ fontFamily: "sans-serif", maxWidth: 600, margin: "2rem auto" }}>
      <h1>Todo</h1>
      <UnauthenticatedTemplate>
        <button onClick={() => instance.loginRedirect({ scopes: apiScopes })}>Sign in</button>
      </UnauthenticatedTemplate>
      <AuthenticatedTemplate>
        <Todos />
      </AuthenticatedTemplate>
    </div>
  );
}
