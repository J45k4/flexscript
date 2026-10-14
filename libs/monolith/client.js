// Small DOM adapter: keyed patches, local input state, actions, and reconnect.
(() => {
  const find = key => document.querySelector(`[data-mkey="${CSS.escape(key)}"]`);
  const tokenMeta = document.querySelector('meta[name="monolith-token"]');
  let revision = -1;
  let busy = false;
  const message = (selector, text) => document.querySelectorAll(selector).forEach(node => { node.textContent = text; });
  const status = text => message('[data-mono-status]', text);
  const error = text => message('[data-mono-error]', text);
  // Reconnect snapshots reuse nodes. Draft values, focus, and selection stay local.
  function reconcile(current, incoming) {
    const localInput = current.matches('input:not([type="checkbox"]):not([type="radio"]):not([type="hidden"]), textarea, select');
    const draft = localInput ? current.value : undefined;
    for (const attr of [...current.attributes]) {
      if (!incoming.hasAttribute(attr.name) && !(localInput && attr.name === 'value')) current.removeAttribute(attr.name);
    }
    for (const attr of incoming.attributes) {
      if (!(localInput && attr.name === 'value')) current.setAttribute(attr.name, attr.value);
    }
    if (current.matches('input[type="checkbox"]')) current.checked = incoming.checked;
    if (!incoming.children.length) {
      if (!current.matches('input') && !localInput) current.textContent = incoming.textContent;
      return current;
    }
    const wanted = new Set();
    let previous = null;
    for (const child of [...incoming.children]) {
      const key = child.dataset.mkey;
      let target = [...current.children].find(el => !wanted.has(el) && (key
        ? el.dataset.mkey === key
        : !el.dataset.mkey && el.tagName === child.tagName && el.getAttribute('name') === child.getAttribute('name')));
      if (target && target.tagName === child.tagName) reconcile(target, child);
      else target = child;
      wanted.add(target);
      const before = previous ? previous.nextElementSibling : current.firstElementChild;
      if (target !== before) current.insertBefore(target, before);
      previous = target;
    }
    for (const child of [...current.children]) if (!wanted.has(child)) child.remove();
    if (localInput) current.value = draft;
    return current;
  }
  function position(node, op) {
    const parent = find(op.parent);
    if (!parent) throw new Error('Missing patch parent');
    const after = op.after ? find(op.after) : null;
    parent.insertBefore(node, after ? after.nextElementSibling : parent.firstElementChild);
  }
  function apply(op) {
    let node = find(op.key);
    if (op.op === 'insert') {
      const template = document.createElement('template');
      template.innerHTML = op.html;
      const incoming = template.content.firstElementChild;
      if (node) reconcile(node, incoming);
      else position(incoming, op);
      return;
    }
    if (!node) throw new Error('Missing patch node');
    if (op.op === 'remove') node.remove();
    else if (op.op === 'move') position(node, op);
    else if (op.op === 'text') node.textContent = op.value;
    else if (op.op === 'checked') node.checked = op.value;
    else if (op.op === 'hidden') node.hidden = op.value;
    else if (op.op === 'class') node.className = op.value;
    else if (op.op === 'label') node.setAttribute('aria-label', op.value);
    else if (op.op === 'placeholder') node.placeholder = op.value;
    else if (op.op === 'attribute') {
      if (op.value === null) node.removeAttribute(op.name);
      else node.setAttribute(op.name, op.value);
      if (node.matches('form') && ['data-action', 'data-id'].includes(op.name)) {
        const field = node.querySelector(`input[name="${op.name === 'data-action' ? 'action' : 'id'}"]`);
        if (field) field.value = op.value || '';
      }
    }
    else throw new Error('Unknown UI operation');
  }
  const events = new EventSource('/events');
  events.onmessage = event => {
    try {
      const message = JSON.parse(event.data);
      if (!message.reset && message.revision <= revision) return;
      if (!message.reset && message.revision !== revision + 1) throw new Error('Missed UI revision');
      message.ops.forEach(apply);
      revision = message.revision;
      tokenMeta.content = message.token;
      document.querySelectorAll('input[name="token"]').forEach(el => { el.value = message.token; });
      status('Live');
    } catch (_) { events.close(); status('Reload to reconnect'); error('The view could not synchronize. Reload this page.'); }
  };
  events.onerror = () => status('Reconnecting…');
  async function action(name, id, fields = new URLSearchParams()) {
    if (busy) return false;
    busy = true;
    error('');
    try {
      const body = new URLSearchParams(fields);
      body.set('token', tokenMeta.content);
      body.set('action', name);
      body.delete('id');
      if (id) body.set('id', id);
      const response = await fetch('/action', { method: 'POST', headers: { Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' }, body });
      if (!response.ok) throw new Error(`Action rejected (${response.status}).`);
      return true;
    } catch (e) { error(e.message); return false; }
    finally { busy = false; }
  }
  document.addEventListener('submit', async event => {
    const form = event.target;
    if (!form.matches('form[data-action]')) return;
    event.preventDefault();
    const trigger = event.submitter?.dataset.action ? event.submitter : form;
    const fields = new URLSearchParams(new FormData(form));
    if (event.submitter?.name) fields.set(event.submitter.name, event.submitter.value);
    const drafts = [...form.querySelectorAll('[data-mono-clear]')].map(node => [node, node.value]);
    if (await action(trigger.dataset.action, trigger.dataset.id ?? form.dataset.id, fields)) {
      for (const [node, submitted] of drafts) if (node.value === submitted) node.value = '';
      if (drafts.length && form.contains(document.activeElement)) drafts[0][0].focus();
    }
  });
  document.addEventListener('change', async event => {
    const target = event.target;
    if (!target.matches('input[type="checkbox"][data-action], select[data-action]')) return;
    const previous = !target.checked;
    const fields = new URLSearchParams();
    if (target.name) fields.set(target.name, target.matches('select') ? target.value : String(target.checked));
    if (!(await action(target.dataset.action, target.dataset.id, fields)) && !target.matches('select')) target.checked = previous;
  });
  document.addEventListener('click', event => {
    const target = event.target.closest('button[data-action], a[data-action]');
    if (!target || target.matches('button[type="submit"]')) return;
    event.preventDefault();
    action(target.dataset.action, target.dataset.id);
  });
})();
