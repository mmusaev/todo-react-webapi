using System.Collections.Concurrent;
using Microsoft.Identity.Web;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration);

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("TodoRead", p => p.RequireRole("Admin", "User"))
    .AddPolicy("TodoWrite", p => p.RequireRole("Admin"));

var origins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod()));

builder.Services.AddSingleton<TodoStore>();

var app = builder.Build();

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/", () => "Todo API");

var todos = app.MapGroup("/api/todos");

todos.MapGet("/", (TodoStore s) => s.All()).RequireAuthorization("TodoRead");
todos.MapGet("/{id:guid}", (Guid id, TodoStore s) => s.Get(id) is { } t ? Results.Ok(t) : Results.NotFound())
    .RequireAuthorization("TodoRead");

todos.MapPost("/", (TodoInput input, TodoStore s) =>
{
    if (string.IsNullOrWhiteSpace(input.Title)) return Results.BadRequest("Title is required.");
    var t = s.Add(input);
    return Results.Created($"/api/todos/{t.Id}", t);
}).RequireAuthorization("TodoWrite");

todos.MapPut("/{id:guid}", (Guid id, TodoInput input, TodoStore s) =>
{
    if (string.IsNullOrWhiteSpace(input.Title)) return Results.BadRequest("Title is required.");
    return s.Update(id, input) is { } t ? Results.Ok(t) : Results.NotFound();
}).RequireAuthorization("TodoWrite");

todos.MapDelete("/{id:guid}", (Guid id, TodoStore s) => s.Remove(id) ? Results.NoContent() : Results.NotFound())
    .RequireAuthorization("TodoWrite");

app.Run();

record Todo(Guid Id, string Title, bool IsDone);
record TodoInput(string Title, bool IsDone);

class TodoStore
{
    private readonly ConcurrentDictionary<Guid, Todo> _items = new();

    public TodoStore()
    {
        foreach (var title in new[] { "Learn MSAL", "Deploy to Azure" })
            Add(new TodoInput(title, false));
    }

    public IEnumerable<Todo> All() => _items.Values.OrderBy(t => t.Title);
    public Todo? Get(Guid id) => _items.GetValueOrDefault(id);

    public Todo Add(TodoInput i)
    {
        var t = new Todo(Guid.NewGuid(), i.Title.Trim(), i.IsDone);
        _items[t.Id] = t;
        return t;
    }

    public Todo? Update(Guid id, TodoInput i)
    {
        if (!_items.ContainsKey(id)) return null;
        var t = new Todo(id, i.Title.Trim(), i.IsDone);
        _items[id] = t;
        return t;
    }

    public bool Remove(Guid id) => _items.TryRemove(id, out _);
}
