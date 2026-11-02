using System.Collections.Concurrent;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Identity.Web;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration);

builder.Services.AddTransient<IClaimsTransformation, PermissionClaimsTransformation>();
builder.Services.AddAuthorizationBuilder()
    .AddPolicy(Permissions.TodosRead, p => p.RequireClaim(Permissions.ClaimType, Permissions.TodosRead))
    .AddPolicy(Permissions.TodosWrite, p => p.RequireClaim(Permissions.ClaimType, Permissions.TodosWrite));

var origins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod()));

builder.Services.AddSingleton<TodoStore>();

var app = builder.Build();

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/", () => "Todo API");

app.MapGet("/api/permissions", (ClaimsPrincipal user) => new
{
    Roles = user.FindAll(PermissionClaimsTransformation.IsRole).Select(c => c.Value).Distinct().Order(),
    Permissions = user.FindAll(Permissions.ClaimType).Select(c => c.Value).Distinct().Order(),
}).RequireAuthorization();

var todos = app.MapGroup("/api/todos");

todos.MapGet("/", (TodoStore s) => s.All()).RequireAuthorization(Permissions.TodosRead);
todos.MapGet("/{id:guid}", (Guid id, TodoStore s) => s.Get(id) is { } t ? Results.Ok(t) : Results.NotFound())
    .RequireAuthorization(Permissions.TodosRead);

todos.MapPost("/", (TodoInput input, TodoStore s) =>
{
    if (string.IsNullOrWhiteSpace(input.Title)) return Results.BadRequest("Title is required.");
    var t = s.Add(input);
    return Results.Created($"/api/todos/{t.Id}", t);
}).RequireAuthorization(Permissions.TodosWrite);

todos.MapPut("/{id:guid}", (Guid id, TodoInput input, TodoStore s) =>
{
    if (string.IsNullOrWhiteSpace(input.Title)) return Results.BadRequest("Title is required.");
    return s.Update(id, input) is { } t ? Results.Ok(t) : Results.NotFound();
}).RequireAuthorization(Permissions.TodosWrite);

todos.MapDelete("/{id:guid}", (Guid id, TodoStore s) => s.Remove(id) ? Results.NoContent() : Results.NotFound())
    .RequireAuthorization(Permissions.TodosWrite);

app.Run();

static class Permissions
{
    public const string ClaimType = "permission";
    public const string TodosRead = "todos:read";
    public const string TodosWrite = "todos:write";

    public static readonly IReadOnlyDictionary<string, string[]> ByRole = new Dictionary<string, string[]>
    {
        ["Admin"] = [TodosRead, TodosWrite],
        ["User"] = [TodosRead],
    };
}

class PermissionClaimsTransformation : IClaimsTransformation
{
    public static bool IsRole(Claim c) => c.Type is "roles" or ClaimTypes.Role;

    public Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
    {
        if (principal.Identity is not ClaimsIdentity identity || !identity.IsAuthenticated
            || identity.HasClaim(c => c.Type == Permissions.ClaimType))
            return Task.FromResult(principal);

        var permissions = principal.Claims.Where(IsRole)
            .SelectMany(c => Permissions.ByRole.GetValueOrDefault(c.Value) ?? [])
            .Distinct();
        // Clone: the incoming principal may be shared across concurrent requests.
        var clone = new ClaimsPrincipal(principal.Identities.Select(i => i.Clone()));
        var cloned = (ClaimsIdentity)clone.Identity!;
        foreach (var p in permissions) cloned.AddClaim(new Claim(Permissions.ClaimType, p));
        return Task.FromResult(clone);
    }
}

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
