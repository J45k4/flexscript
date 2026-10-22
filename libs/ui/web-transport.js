
(() => {
  const renderer = new FlexscriptUi(document.querySelector('[data-mkey="mount"]'), async event => {
    const body = new URLSearchParams({token: document.querySelector('meta[name="monolith-token"]').content, action: event.action});
    if (event.action_id) body.set('id', String(event.action_id));
    body.set('ui_key', event.key); body.set('ui_type', event.type); body.set('ui_value', String(event.value));
    try { const reply = await fetch('/action', {method: 'POST', headers: {Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded'}, body});
      if (!reply.ok) throw new Error('UI action failed: ' + reply.status);
    } catch (error) { document.querySelector('[data-ui-error]').textContent = error.message; }
  });
  let revision = -1;
  const events = new EventSource('/events');
  events.onmessage = event => {
    try { const packet = JSON.parse(event.data);
      if (!packet.reset && packet.revision <= revision) return;
      if (!packet.reset && packet.revision !== revision + 1) throw new Error('Missed UI revision');
      renderer.apply({version: 1, ops: packet.ops}); revision = packet.revision;
      document.querySelector('meta[name="monolith-token"]').content = packet.token;
    } catch (error) { events.close(); document.querySelector('[data-ui-error]').textContent = error.message; }
  };
})();
