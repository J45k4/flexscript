// Native DOM adapter for Flexscript UI wire ABI1. No templates or HTML parsing.
class FlexscriptUi {
  constructor(mount, events, platform = {}) {
    this.mount = mount;
    this.events = events;
    this.platform = platform;
    this.nodes = new Map();
  }
  need(key) {
    const node = this.nodes.get(key);
    if (!node) throw new Error(`Missing UI node: ${key}`);
    return node;
  }
  emit(node, type, value) {
    if (node.action) this.events({key: node.key, action: node.action, action_id: node.action_id, type, value});
  }
  container(node) { return ["column", "row", "scroll", "hscroll", "stack"].includes(node.kind); }
  create(key, kind, props = {}) {
    const tags = {column: 'div', row: 'div', scroll: 'div', text: 'span', button: 'button', input: Number(props.single_line) > 0 ? 'input' : 'textarea', check: 'input', image: 'img', stack: 'div', hscroll: 'div', progress: 'progress'};
    if (!tags[kind]) throw new Error(`Unsupported UI widget: ${kind}`);
    const el = document.createElement(tags[kind]);
    el.dataset.uiKey = key;
    if (kind === 'button') el.type = 'button';
    if (kind === 'check') el.type = 'checkbox';
    if (kind === 'progress') el.max = 1000;
    const node = {key, kind, el, props: {}, text: '', action: '', action_id: 0, hidden: false};
    this.nodes.set(key, node);
    if (kind === 'input' || kind === 'check') {
      if (kind === 'input') el.addEventListener('keydown', event => {
        if (event.key === 'Enter' && !event.shiftKey && !event.isComposing && node.props.ime === 'send') { event.preventDefault(); this.emit(node, 'submit', el.value); }
      });
      el.addEventListener(kind === 'input' ? 'input' : 'change', event => {
        event.stopPropagation(); this.emit(node, 'change', kind === 'check' ? el.checked : el.value);
      });
    } else {
      el.addEventListener('click', event => {
        if (node.action) { event.stopPropagation(); this.emit(node, 'click', null); }
      });
    }
    return node;
  }
  properties(node, props) {
    const {el, kind} = node, prior = node.props;
    node.props = {...props};
    const cssColor = value => /^#[0-9a-f]{8}$/i.test(value ?? '') ? '#'+value.slice(3)+value.slice(1,3) : value;
    const px = (name, fallback = 0) => `${Number(props[name] ?? fallback)}px`;
    const dimension = name => props[name] == null ? '' : Number(props[name]) === -1 ? '100%' : Number(props[name]) === -2 ? 'auto' : px(name);
    const container = kind === 'column' || kind === 'row';
    Object.assign(el.style, {
      boxSizing: 'border-box', minWidth: '0', flexShrink: '0',
      display: node.hidden ? 'none' : container ? 'flex' : kind === 'text' ? 'block' : '',
      flexDirection: kind === 'row' ? 'row' : 'column',
      alignItems: kind === 'row' ? 'center' : 'stretch',
      overflow: kind === 'scroll' || kind === 'hscroll' ? 'auto' : '',
      overflowY: kind === 'hscroll' ? 'hidden' : '',
      position: kind === 'stack' ? 'relative' : el.style.position,
      whiteSpace: 'pre-wrap', opacity: Number(props.alpha ?? 100) / 100,
      padding: `${px('padding_y', props.padding ?? 0)} ${px('padding_x', props.padding ?? 0)}`,
      gap: px('gap'), borderRadius: px('radius'),
      border: `${px('border_width')} solid ${cssColor(props.border_color) ?? 'transparent'}`,
      background: cssColor(props.background) ?? 'transparent', color: cssColor(props.color) ?? 'black',
      fontFamily: props.font === 'monospace' ? 'monospace' : 'sans-serif', fontWeight: props.font === 'medium' ? '500' : '400',
      fontSize: px('size', 14), lineHeight: 'normal',
      width: dimension('width'), height: dimension('height'),
      minHeight: px('min_height'), flexGrow: props.weight ?? '0', flexBasis: Number(props.weight) > 0 ? '0px' : 'auto',
      textAlign: props.align ?? 'start',
    });
    if (props.align && container) el.style.justifyContent = ({start: 'flex-start', center: 'center', end: 'flex-end'})[props.align] ?? 'flex-start';
    el.hidden = node.hidden;
    el.disabled = props.enabled === 'false';
    if (kind === 'input') {
      el.placeholder = node.text;
      el.autocapitalize = ['sentences', 'words', 'characters'].includes(props.autocapitalize) ? props.autocapitalize : 'none';
      el.rows = Number(props.min_lines ?? 1);
      el.style.resize = 'none';
      if (prior.value !== props.value && el.value !== (props.value ?? '')) el.value = props.value ?? '';
    } else if (kind === 'check') {
      el.style.accentColor = props.color ?? '';
    } else if (kind === 'text' || kind === 'button') {
      const content = props.timestamp == null ? node.text : new Intl.DateTimeFormat(undefined,{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}).format(new Date(Number(props.timestamp)));
      const signature = content + '\u0000' + (props.runs ?? '');
      if (signature !== node.renderedText) {
        if (props.runs) {
          el.replaceChildren();
          for (const run of JSON.parse(props.runs)) {
            const href = run.href && /^https?:\/\//.test(run.href) ? run.href : null;
            const span = document.createElement(href ? 'a' : 'span');
            span.textContent = run.text;
            if (href) { span.href = href; span.rel = 'noreferrer'; }
            if (run.style & 1) span.style.fontWeight = 'bold';
            if (run.style & 2) span.style.fontFamily = 'monospace';
            if (run.style & 4) span.style.fontSize = '1.12em';
            if (run.style & 8) span.style.fontSize = '.88em';
            if (run.color) span.style.color = run.color;
            el.append(span);
          }
        } else el.textContent = content;
        node.renderedText = signature;
      }
      if (props.max_lines) { el.style.display = node.hidden ? 'none' : '-webkit-box'; el.style.webkitBoxOrient = 'vertical'; el.style.webkitLineClamp = props.max_lines; el.style.overflow = 'hidden'; }
      el.style.userSelect = Number(props.selectable) ? 'text' : '';
    }
    if (props.description || kind === 'check') el.setAttribute('aria-label', props.description ?? node.text);
    else el.removeAttribute('aria-label');
    if (kind === 'image' && prior.source !== props.source) {
      const source = this.platform.imageSource ? this.platform.imageSource(props.source) : props.source;
      if (source) el.src = source; else el.removeAttribute('src');
      el.style.objectFit = 'contain';
    }
    if (kind === 'progress') { el.value = Number(props.progress ?? 0); el.style.accentColor = props.color ?? ''; }
  }
  position(node, parentKey, after) {
    const parent = parentKey === 'mount' ? this.mount : this.need(parentKey).el;
    const sibling = after ? this.need(after).el : null;
    if (sibling && sibling.parentElement !== parent) throw new Error('UI sibling has a different parent');
    const parentNode = parentKey === 'mount' ? null : this.need(parentKey);
    if (parentNode?.kind === 'stack') { node.el.style.position = 'absolute'; node.el.style.inset = '0'; }
    else { node.el.style.position = node.kind === 'stack' ? 'relative' : ''; node.el.style.inset = ''; }
    if (parentNode?.kind === 'hscroll') { node.el.style.whiteSpace = 'pre'; node.el.style.minWidth = 'max-content'; }
    const before = sibling ? sibling.nextElementSibling : parent.firstElementChild;
    if (before !== node.el) parent.insertBefore(node.el, before);
  }
  remove(node) {
    if (this.container(node)) for (const child of [...node.el.children]) this.remove(this.need(child.dataset.uiKey));
    node.el.remove(); this.nodes.delete(node.key);
  }
  tree(descriptor) {
    let node = this.nodes.get(descriptor.key);
    if (node && node.kind !== descriptor.kind) { this.remove(node); node = null; }
    if (!node) node = this.create(descriptor.key, descriptor.kind, descriptor.props);
    Object.assign(node, {text: descriptor.text, action: descriptor.action, action_id: descriptor.action_id, hidden: descriptor.hidden});
    this.properties(node, descriptor.props);
    if (node.kind === 'check') node.el.checked = descriptor.checked;
    const wanted = new Set(); let after = '';
    for (const child of descriptor.children) {
      const next = this.tree(child); this.position(next, node.key, after); after = next.key; wanted.add(next.key);
    }
    if (this.container(node)) for (const child of [...node.el.children]) if (!wanted.has(child.dataset.uiKey)) this.remove(this.need(child.dataset.uiKey));
    return node;
  }
  apply(packet) {
    if (packet.version !== 1) throw new Error('Unsupported Flexscript UI ABI');
    const following = [...this.nodes.values()].filter(node => node.kind === 'scroll' && Number(node.props.follow) && node.el.scrollHeight-(node.el.scrollTop+node.el.clientHeight)<100);
    const focus = document.activeElement;
    const selection = focus && typeof focus.selectionStart === 'number' ? [focus.selectionStart, focus.selectionEnd] : null;
    for (const op of packet.ops) {
      if (op.op === 'insert') { this.position(this.tree(op.node), op.parent, op.after); continue; }
      const node = this.need(op.key);
      switch (op.op) {
        case 'remove': this.remove(node); break;
        case 'move': this.position(node, op.parent, op.after); break;
        case 'checked': node.el.checked = op.value; break;
        case 'hidden': node.hidden = op.value; this.properties(node, node.props); break;
        case 'text': case 'label': case 'placeholder': node.text = op.value; this.properties(node, node.props); break;
        case 'attribute':
          if (op.name === 'action') node.action = op.value ?? '';
          else if (op.name === 'action_id') node.action_id = Number(op.value ?? 0);
          else {
            const props = {...node.props};
            if (op.value === null) delete props[op.name]; else props[op.name] = op.value;
            this.properties(node, props);
          }
          break;
        default: throw new Error(`Unsupported UI operation: ${op.op}`);
      }
    }
    for (const node of following) if (node.el.isConnected) node.el.scrollTop = node.el.scrollHeight;
    if (focus?.isConnected && document.activeElement !== focus) {
      focus.focus({preventScroll: true});
      if (selection) focus.setSelectionRange(...selection);
    }
  }
}
