Deno.serve(() => new Response(JSON.stringify({ error: 'Setup deshabilitado' }), {
  status: 410,
  headers: { 'Content-Type': 'application/json' },
}))