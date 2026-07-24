:::{admonition} Working in a different workspace?
:class: tip

The shadow and the global integrity guard protect `claude` in *every*
folder — a workspace needs nothing added to it to be safe.

The trade-off is that the `just` recipes and project commands like
`/verify-sandbox` ship **with the claude-sandbox clone**, so they are only
available when Claude's working directory is that clone. To use them, `cd` into
the clone (e.g. `/workspaces/claude-sandbox`), run what you need, then
return to your work — dropping back to the clone like this is expected and fine.
:::
