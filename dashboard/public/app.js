async function fetchJSON(url, options) {
  const res = await fetch(url, options);
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Request failed: ${res.status} ${res.statusText} ${text}`);
  }
  return res.json();
}

function statusBadge(status) {
  const s = (status || '').toLowerCase();
  if (s === 'active') return '<span class="badge badge-status-active">active</span>';
  if (s === 'failed') return '<span class="badge badge-status-failed">failed</span>';
  if (s === 'deploying') return '<span class="badge badge-status-deploying">deploying</span>';
  return `<span class="badge">${status || 'unknown'}</span>`;
}

function formatIPs(vm_ip, mycelium_ip) {
  const ips = [];
  if (vm_ip) ips.push(`<span class="ip-text">${vm_ip}</span>`);
  if (mycelium_ip) ips.push(`<span class="ip-text">${mycelium_ip}</span>`);
  return ips.join('<br/>') || '<span class="ip-text">N/A</span>';
}

function showLogPanel(title, subtitle) {
  const panel = document.getElementById('log-panel');
  const placeholder = document.getElementById('output-placeholder');
  const titleEl = document.getElementById('log-title');
  const subtitleEl = document.getElementById('log-subtitle');
  titleEl.textContent = title;
  subtitleEl.textContent = subtitle || '';
  panel.classList.remove('hidden');
  if (placeholder) placeholder.classList.add('hidden');
}

function hideLogPanel() {
  const panel = document.getElementById('log-panel');
  const shellPanel = document.getElementById('shell-panel');
  const placeholder = document.getElementById('output-placeholder');
  if (panel) panel.classList.add('hidden');
  if (placeholder && (!shellPanel || shellPanel.classList.contains('hidden'))) {
    placeholder.classList.remove('hidden');
  }
}

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function ansiToHtml(str) {
  const ESC = '\u001b[';
  let result = '';
  let i = 0;
  let openSpan = false;

  while (i < str.length) {
    const idx = str.indexOf(ESC, i);
    if (idx === -1) {
      result += escapeHtml(str.slice(i));
      break;
    }

    result += escapeHtml(str.slice(i, idx));
    const end = str.indexOf('m', idx);
    if (end === -1) {
      result += escapeHtml(str.slice(idx));
      break;
    }

    const codeStr = str.slice(idx + ESC.length, end);
    const codes = codeStr
      .split(';')
      .map((c) => parseInt(c, 10))
      .filter((n) => !Number.isNaN(n));

    if (openSpan) {
      result += '</span>';
      openSpan = false;
    }

    if (codes.length === 0 || codes.includes(0)) {
      // Reset, no styles
    } else {
      const classes = [];
      codes.forEach((c) => {
        if (c === 1) classes.push('ansi-bold');
        if (c >= 30 && c <= 37) classes.push(`ansi-fg-${c - 30}`);
        if (c >= 90 && c <= 97) classes.push(`ansi-fg-bright-${c - 90}`);
      });
      if (classes.length) {
        result += `<span class="${classes.join(' ')}">`;
        openSpan = true;
      }
    }

    i = end + 1;
  }

  if (openSpan) {
    result += '</span>';
  }

  return result;
}

function setLogContent(text) {
  const el = document.getElementById('log-content');
  if (!el) return;
  el.innerHTML = ansiToHtml(text || '');
}

let commandsCache = [];
let deploymentContext = null;
let activeShellSession = null;
let shellEventSource = null;
let shellBuffer = '';

function setShellContent(text) {
  const el = document.getElementById('shell-content');
  if (!el) return;
  el.innerHTML = ansiToHtml(text || '');
}

function isDeploymentScopedCommand(cmd) {
  const id = cmd && (cmd.id || cmd.command);
  return id === 'status:app' || id === 'logs:app' || id === 'ssh' || id === 'exec' || id === 'address';
}

function getInitialStateForCommand(cmd) {
  const initial = { args: {}, flags: {} };
  if (!deploymentContext) return initial;

  const id = cmd && (cmd.id || cmd.command);
  const dep = deploymentContext;
  if (!id || !dep) return initial;

  if (id === 'status:app' || id === 'logs:app' || id === 'ssh' || id === 'address') {
    initial.args.app = dep.id;
  } else if (id === 'exec') {
    initial.args.app = dep.id;
    initial.args.remote_cmd = 'ls';
  }

  return initial;
}

function updateDeploymentSelectionUI() {
  const tbody = document.getElementById('deployments-body');
  if (!tbody) return;

  const rows = tbody.querySelectorAll('tr');
  rows.forEach((row) => {
    const id = row.getAttribute('data-deployment-id');
    if (deploymentContext && id === deploymentContext.id) {
      row.classList.add('deployment-selected');
    } else {
      row.classList.remove('deployment-selected');
    }
  });
}

function updateCommandsContextUI() {
  const valueEl = document.getElementById('commands-context-value');
  const metaEl = document.getElementById('commands-context-meta');
  const clearBtn = document.getElementById('commands-context-clear');

  const deploymentButtons = document.querySelectorAll('.command-item[data-scope="deployment"]');
  const hasContext = !!deploymentContext;

  if (valueEl && metaEl && clearBtn) {
    if (!hasContext) {
      valueEl.textContent = 'Global (tfgrid-compose)';
      metaEl.textContent = 'No deployment selected. All commands run without deployment context.';
      clearBtn.classList.add('hidden');
    } else {
      const appName = deploymentContext.app_name || '';
      valueEl.textContent = appName
        ? `Deployment ${deploymentContext.id} (${appName})`
        : `Deployment ${deploymentContext.id}`;
      metaEl.textContent = 'Commands in "For deployment" will use this deployment where applicable.';
      clearBtn.classList.remove('hidden');
    }
  }

  deploymentButtons.forEach((btn) => {
    btn.disabled = !hasContext;
  });

  updateDeploymentSelectionUI();
}

function setDeploymentContext(deployment) {
  deploymentContext = deployment || null;
  updateCommandsContextUI();
}

function renderCommandList(commands) {
  const container = document.getElementById('commands-list');
  if (!container) return;

  if (!commands.length) {
    container.innerHTML = '<div class="card"><div class="card-body">No commands available.</div></div>';
    return;
  }

  const globalGrouped = {};
  const deploymentGrouped = {};

  commands.forEach((cmd) => {
    const cat = cmd.category || 'other';
    const target = isDeploymentScopedCommand(cmd) ? deploymentGrouped : globalGrouped;
    if (!target[cat]) target[cat] = [];
    target[cat].push(cmd);
  });

  container.innerHTML = '';

  function renderGroup(title, badgeText, grouped, scope) {
    const cats = Object.keys(grouped);
    if (!cats.length) return;

    const groupEl = document.createElement('div');
    groupEl.className = 'commands-group';

    const header = document.createElement('div');
    header.className = 'commands-group-header';
    const h = document.createElement('h3');
    h.textContent = title;
    const badge = document.createElement('span');
    badge.className = 'commands-group-badge';
    badge.textContent = badgeText;
    header.appendChild(h);
    header.appendChild(badge);
    groupEl.appendChild(header);

    const body = document.createElement('div');
    body.className = 'commands-group-body';

    cats.sort().forEach((cat) => {
      const section = document.createElement('div');
      section.className = 'commands-category';

      const heading = document.createElement('div');
      heading.className = 'commands-category-title';
      heading.textContent = cat.charAt(0).toUpperCase() + cat.slice(1);
      section.appendChild(heading);

      (grouped[cat] || []).forEach((cmd) => {
        const btn = document.createElement('button');
        btn.className = 'btn btn-ghost command-item';
        btn.type = 'button';
        btn.dataset.scope = scope;
        btn.textContent = cmd.label || cmd.command;
        btn.addEventListener('click', () => {
          const initial = getInitialStateForCommand(cmd);
          renderCommandDetail(cmd, initial);
        });
        section.appendChild(btn);
      });

      body.appendChild(section);
    });

    groupEl.appendChild(body);
    container.appendChild(groupEl);
  }

  renderGroup('Global CLI', 'GLOBAL', globalGrouped, 'global');
  renderGroup('For deployment', 'DEPLOYMENT', deploymentGrouped, 'deployment');

  updateCommandsContextUI();
}

function buildPreviewCommand(cmd, form) {
  const parts = ['tfgrid-compose', cmd.command];

  (cmd.args || []).forEach((arg) => {
    const el = form.querySelector(`[name="arg-${arg.name}"]`);
    if (!el) return;
    const val = el.value.trim();
    if (!val) return;
    parts.push(val);
  });

  (cmd.flags || []).forEach((flag) => {
    const name = flag.name;
    const inputName = `flag-${name}`;
    const el = form.querySelector(`[name="${inputName}"]`);
    if (!el) return;

    if (flag.type === 'boolean') {
      if (el.checked) {
        parts.push(`--${name}`);
      }
    } else {
      const val = el.value.trim();
      if (!val) return;
      parts.push(`--${name}=${val}`);
    }
  });

  return parts.join(' ');
}

function renderCommandDetail(cmd, initial) {
  const container = document.getElementById('command-detail');
  if (!container) return;

  const args = cmd.args || [];
  const flags = cmd.flags || [];

  const initialArgs = (initial && initial.args) || {};
  const initialFlags = (initial && initial.flags) || {};

  let html = `
    <div class="card">
      <div class="card-header">
        <h3 class="card-title">${cmd.label || cmd.command}</h3>
        <p class="card-subtitle">${cmd.description || ''}</p>
      </div>
      <div class="card-body">
        <form id="command-form">
  `;

  if (args.length) {
    html += '<div class="form-section"><h4>Arguments</h4>';
    args.forEach((arg) => {
      const initialVal = initialArgs[arg.name] || '';
      let optionsHtml = '';
      if (typeof arg.description === 'string' && arg.description.includes('|')) {
        const tokens = arg.description
          .split('|')
          .map((t) => t.trim())
          .filter((t) => t && !t.includes(' '));
        if (tokens.length) {
          optionsHtml = '<div class="arg-options" data-arg="' + arg.name + '">';
          tokens.forEach((token) => {
            optionsHtml += `<button type="button" class="btn btn-ghost btn-small arg-chip" data-value="${token}">${token}</button>`;
          });
          optionsHtml += '</div>';
        }
      }
      html += `
        <div class="form-field">
          <label>
            <span>${arg.name}${arg.required ? ' *' : ''}</span>
            <input type="text" name="arg-${arg.name}" value="${initialVal}" placeholder="${arg.description || ''}" />
          </label>
          ${optionsHtml}
        </div>
      `;
    });
    html += '</div>';
  }

  if (flags.length) {
    html += '<div class="form-section"><h4>Flags</h4>';
    flags.forEach((flag) => {
      if (flag.type === 'boolean') {
        const checkedAttr = initialFlags[flag.name] ? ' checked' : '';
        html += `
          <div class="form-field">
            <label class="checkbox-label">
              <input type="checkbox" name="flag-${flag.name}"${checkedAttr} />
              <span>--${flag.name}${flag.alias ? ` (${flag.alias})` : ''} - ${flag.description || ''}</span>
            </label>
          </div>
        `;
      } else {
        const initialVal = initialFlags[flag.name] || '';
        html += `
          <div class="form-field">
            <label>
              <span>--${flag.name}${flag.alias ? ` (${flag.alias})` : ''}</span>
              <input type="text" name="flag-${flag.name}" value="${initialVal}" placeholder="${flag.description || ''}" />
            </label>
          </div>
        `;
      }
    });
    html += '</div>';
  }

  html += `
          <div class="form-section">
            <h4>Preview</h4>
            <pre id="command-preview" class="log-content"></pre>
          </div>
          <div class="form-actions">
            <button type="submit" class="btn btn-primary">Run Command</button>
          </div>
        </form>
      </div>
    </div>
  `;

  container.innerHTML = html;

  const form = document.getElementById('command-form');
  const previewEl = document.getElementById('command-preview');

  function updatePreview() {
    if (!previewEl) return;
    previewEl.textContent = buildPreviewCommand(cmd, form);
  }

  if (form) {
    const chips = form.querySelectorAll('.arg-chip');
    chips.forEach((chip) => {
      chip.addEventListener('click', () => {
        const value = chip.getAttribute('data-value') || '';
        const wrapper = chip.closest('.arg-options');
        const argName = wrapper && wrapper.getAttribute('data-arg');
        if (!argName) return;
        const input = form.querySelector(`[name="arg-${argName}"]`);
        if (!input) return;
        input.value = value;
        updatePreview();
      });
    });

    form.addEventListener('input', updatePreview);
    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      const argsPayload = {};
      const flagsPayload = {};

      (cmd.args || []).forEach((arg) => {
        const el = form.querySelector(`[name="arg-${arg.name}"]`);
        if (!el) return;
        const val = el.value.trim();
        if (val) {
          argsPayload[arg.name] = val;
        }
      });

      (cmd.flags || []).forEach((flag) => {
        const name = flag.name;
        const el = form.querySelector(`[name="flag-${name}"]`);
        if (!el) return;
        if (flag.type === 'boolean') {
          flagsPayload[name] = el.checked;
        } else {
          const val = el.value.trim();
          if (val) flagsPayload[name] = val;
        }
      });

      const preview = buildPreviewCommand(cmd, form);
      showLogPanel(cmd.label || cmd.command, preview);
      setLogContent('Starting command job...');

      const submitButton = form.querySelector('button[type="submit"]');
      const originalText = submitButton ? submitButton.textContent : '';
      if (submitButton) {
        submitButton.disabled = true;
        submitButton.textContent = 'Running...';
      }

      try {
        const res = await fetchJSON('/api/commands/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            commandId: cmd.id || cmd.command,
            args: argsPayload,
            flags: flagsPayload,
          }),
        });
        const jobId = res.job_id;
        if (!jobId) throw new Error('Dashboard backend did not return job_id');
        await pollJob(jobId, submitButton, originalText || 'Run Command');
      } catch (err) {
        setLogContent(`Failed to start command: ${err.message}`);
        if (submitButton) {
          submitButton.disabled = false;
          submitButton.textContent = originalText || 'Run Command';
        }
      }
    });

    updatePreview();
  }
}

async function openShellForDeployment(deployment) {
  try {
    setDeploymentContext(deployment);

    // Close any existing shell session
    if (shellEventSource) {
      shellEventSource.close();
      shellEventSource = null;
    }
    if (activeShellSession && activeShellSession.id) {
      try {
        await fetch(`/api/shells/${activeShellSession.id}/close`, { method: 'POST' });
      } catch (err) {
        // ignore close errors
      }
    }

    const res = await fetchJSON(`/api/deployments/${deployment.id}/shell`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });

    const sessionId = res.session_id;
    if (!sessionId) throw new Error('Dashboard backend did not return session_id');

    activeShellSession = { id: sessionId, deployment };
    shellBuffer = '';

    const panel = document.getElementById('shell-panel');
    const placeholder = document.getElementById('output-placeholder');
    const titleEl = document.getElementById('shell-title');
    const subtitleEl = document.getElementById('shell-subtitle');
    const contentEl = document.getElementById('shell-content');

    if (titleEl) {
      titleEl.textContent = `Shell - ${deployment.id}`;
    }
    if (subtitleEl) {
      subtitleEl.textContent = deployment.app_name || '';
    }
    if (contentEl) {
      contentEl.textContent = '';
    }
    if (panel) {
      panel.classList.remove('hidden');
    }
    if (placeholder) {
      placeholder.classList.add('hidden');
    }

    const es = new EventSource(`/api/shells/${sessionId}/stream`);
    shellEventSource = es;

    es.onmessage = (event) => {
      const line = event.data || '';
      shellBuffer += line + '\n';
      setShellContent(shellBuffer);
    };

    es.addEventListener('close', () => {
      if (panel) panel.classList.add('hidden');
      shellEventSource = null;
      activeShellSession = null;
    });

    es.onerror = () => {
      // Keep the session open; errors are usually transient network issues
    };
  } catch (err) {
    showLogPanel('Shell error', '');
    setLogContent(`Failed to start shell: ${err.message}`);
  }
}

async function sendShellInput() {
  if (!activeShellSession || !activeShellSession.id) return;
  const inputEl = document.getElementById('shell-input');
  if (!inputEl) return;
  const value = (inputEl.value || '').trim();
  if (!value) return;
  inputEl.value = '';

  try {
    await fetch(`/api/shells/${activeShellSession.id}/input`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: value + '\n' }),
    });
  } catch (err) {
    // Swallow errors; shell output panel will reflect any issues
  }
}

async function closeShellPanel() {
  const panel = document.getElementById('shell-panel');
  const logPanel = document.getElementById('log-panel');
  const placeholder = document.getElementById('output-placeholder');
  if (panel) panel.classList.add('hidden');

  if (shellEventSource) {
    shellEventSource.close();
    shellEventSource = null;
  }

  if (activeShellSession && activeShellSession.id) {
    try {
      await fetch(`/api/shells/${activeShellSession.id}/close`, { method: 'POST' });
    } catch (err) {
      // ignore
    }
  }

  activeShellSession = null;

  if (placeholder && (!logPanel || logPanel.classList.contains('hidden'))) {
    placeholder.classList.remove('hidden');
  }
}

function openCommandWithInitial(commandId, initial) {
  if (!commandsCache || !commandsCache.length) {
    showLogPanel('Commands not loaded', '');
    setLogContent('Commands schema is still loading. Try again in a moment.');
    return;
  }

  const cmd = commandsCache.find((c) => c.id === commandId || c.command === commandId);
  if (!cmd) {
    showLogPanel('Command not available', '');
    setLogContent(`The command "${commandId}" is not available in the current commands schema.`);
    return;
  }

  renderCommandDetail(cmd, initial || { args: {}, flags: {} });

  const commandsPanel = document.querySelector('.commands-layout');
  if (commandsPanel && typeof commandsPanel.scrollIntoView === 'function') {
    commandsPanel.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
}

function openAdvancedDeploy(appName) {
  openCommandWithInitial('up', { args: { app: appName }, flags: {} });
}

async function loadCommands() {
  const listContainer = document.getElementById('commands-list');
  const detailContainer = document.getElementById('command-detail');
  if (!listContainer || !detailContainer) return;

  listContainer.innerHTML = '<div class="card"><div class="card-body">Loading commands...</div></div>';
  detailContainer.innerHTML = '';

  try {
    const data = await fetchJSON('/api/commands');
    const commands = (data && data.commands) || [];
    commandsCache = commands;
    renderCommandList(commands);
    if (commands.length > 0) {
      renderCommandDetail(commands[0]);
    }
  } catch (err) {
    listContainer.innerHTML = `<div class="card"><div class="card-body">Failed to load commands: ${err.message}</div></div>`;
  }
}

async function loadPreferences() {
  const wlEl = document.getElementById('preferences-whitelist');
  const blEl = document.getElementById('preferences-blacklist');
  const thEl = document.getElementById('preferences-thresholds');
  if (!wlEl || !blEl || !thEl) return;

  wlEl.innerHTML = '<div class="card-body">Loading whitelist...</div>';
  blEl.innerHTML = '<div class="card-body">Loading blacklist...</div>';
  thEl.innerHTML = '<div class="card-body">Loading preferences...</div>';

  try {
    const data = await fetchJSON('/api/preferences');
    const wl = data.whitelist || { nodes: [], farms: [] };
    const bl = data.blacklist || { nodes: [], farms: [] };
    const prefs = data.preferences || {};

    const wlNodes = (wl.nodes || []).join(', ');
    const wlFarms = (wl.farms || []).join(', ');
    const blNodes = (bl.nodes || []).join(', ');
    const blFarms = (bl.farms || []).join(', ');

    wlEl.innerHTML = `
      <h3 class="card-title">Whitelist</h3>
      <div class="card-body">
        <p><strong>Nodes:</strong> ${wlNodes || '<span class="muted">none</span>'}</p>
        <p><strong>Farms:</strong> ${wlFarms || '<span class="muted">none</span>'}</p>
        <div class="pref-actions">
          <button class="btn btn-ghost btn-small" id="edit-whitelist-nodes">Edit Nodes in CLI Commands</button>
          <button class="btn btn-ghost btn-small" id="edit-whitelist-farms">Edit Farms in CLI Commands</button>
        </div>
      </div>
    `;

    blEl.innerHTML = `
      <h3 class="card-title">Blacklist</h3>
      <div class="card-body">
        <p><strong>Nodes:</strong> ${blNodes || '<span class="muted">none</span>'}</p>
        <p><strong>Farms:</strong> ${blFarms || '<span class="muted">none</span>'}</p>
        <div class="pref-actions">
          <button class="btn btn-ghost btn-small" id="edit-blacklist-nodes">Edit Nodes in CLI Commands</button>
          <button class="btn btn-ghost btn-small" id="edit-blacklist-farms">Edit Farms in CLI Commands</button>
        </div>
      </div>
    `;

    const maxCpu = prefs.max_cpu_usage != null ? `${prefs.max_cpu_usage}%` : '<span class="muted">default</span>';
    const maxDisk = prefs.max_disk_usage != null ? `${prefs.max_disk_usage}%` : '<span class="muted">default</span>';
    const minUptime = prefs.min_uptime_days != null ? `${prefs.min_uptime_days} days` : '<span class="muted">default</span>';

    thEl.innerHTML = `
      <h3 class="card-title">Thresholds</h3>
      <div class="card-body">
        <p><strong>Max CPU Usage:</strong> ${maxCpu}</p>
        <p><strong>Max Disk Usage:</strong> ${maxDisk}</p>
        <p><strong>Min Uptime:</strong> ${minUptime}</p>
        <p class="preferences-note">Global thresholds are applied by tfgrid-compose during node selection.</p>
      </div>
    `;

    const wlNodesBtn = document.getElementById('edit-whitelist-nodes');
    const wlFarmsBtn = document.getElementById('edit-whitelist-farms');
    const blNodesBtn = document.getElementById('edit-blacklist-nodes');
    const blFarmsBtn = document.getElementById('edit-blacklist-farms');

    if (wlNodesBtn) wlNodesBtn.addEventListener('click', () => openCommandWithInitial('whitelist', { args: { subcommand: 'nodes', value: wlNodes }, flags: {} }));
    if (wlFarmsBtn) wlFarmsBtn.addEventListener('click', () => openCommandWithInitial('whitelist', { args: { subcommand: 'farms', value: wlFarms }, flags: {} }));
    if (blNodesBtn) blNodesBtn.addEventListener('click', () => openCommandWithInitial('blacklist', { args: { subcommand: 'nodes', value: blNodes }, flags: {} }));
    if (blFarmsBtn) blFarmsBtn.addEventListener('click', () => openCommandWithInitial('blacklist', { args: { subcommand: 'farms', value: blFarms }, flags: {} }));
  } catch (err) {
    wlEl.innerHTML = `<div class="card-body">Failed to load preferences: ${err.message}</div>`;
    blEl.innerHTML = '';
    thEl.innerHTML = '';
  }
}

async function loadApps() {
  const container = document.getElementById('apps-list');
  container.innerHTML = '<div class="card"><div class="card-body">Loading apps...</div></div>';

  try {
    const data = await fetchJSON('/api/apps');
    const apps = data.apps || [];

    if (!apps.length) {
      container.innerHTML = '<div class="card"><div class="card-body">No apps found in registry.</div></div>';
      return;
    }

    container.innerHTML = '';

    apps.forEach((app) => {
      const card = document.createElement('div');
      card.className = 'card';

      const isAIStack = app.name === 'tfgrid-ai-stack';

      card.innerHTML = `
        <div class="card-header">
          <h3 class="card-title">${app.name}</h3>
          ${isAIStack ? '<span class="card-tag">Flagship</span>' : ''}
        </div>
        <div class="card-body">
          <p>${app.description || ''}</p>
        </div>
        <div class="card-footer">
          <button class="btn btn-primary" data-app="${app.name}" data-kind="quick">Deploy</button>
          <button class="btn btn-ghost btn-small" data-app="${app.name}" data-kind="advanced">Advanced</button>
        </div>
      `;

      const quickBtn = card.querySelector('button[data-kind="quick"]');
      const advancedBtn = card.querySelector('button[data-kind="advanced"]');
      if (quickBtn) {
        quickBtn.addEventListener('click', () => startDeployment(app.name, quickBtn));
      }
      if (advancedBtn) {
        advancedBtn.addEventListener('click', () => openAdvancedDeploy(app.name));
      }

      container.appendChild(card);
    });
  } catch (err) {
    container.innerHTML = `<div class="card"><div class="card-body">Failed to load apps: ${err.message}</div></div>`;
  }
}

async function handleProjectAction(deployment, action, inputEl, button) {
  const projectName = (inputEl && inputEl.value || '').trim();
  if (!projectName) {
    showLogPanel(`Missing project name`, `Deployment ${deployment.id}`);
    setLogContent('Please enter a project name before running this action.');
    return;
  }

  const actionLabel = action.charAt(0).toUpperCase() + action.slice(1);
  const originalText = button.textContent;

  button.disabled = true;
  button.textContent = `${actionLabel}...`;

  showLogPanel(`${actionLabel} ${projectName}`, `Deployment ${deployment.id} (${deployment.app_name || ''})`);
  setLogContent(`Starting tfgrid-compose ${action} ${projectName}...`);

  try {
    const res = await fetchJSON(`/api/deployments/${deployment.id}/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ projectName }),
    });
    const jobId = res.job_id;
    if (!jobId) throw new Error('Dashboard backend did not return job_id');
    await pollJob(jobId, button, originalText);
  } catch (err) {
    setLogContent(`Failed to start ${action}: ${err.message}`);
    button.disabled = false;
    button.textContent = originalText;
  }
}

async function loadDeployments() {
  const tbody = document.getElementById('deployments-body');
  tbody.innerHTML = '<tr><td colspan="6">Loading deployments...</td></tr>';

  try {
    const data = await fetchJSON('/api/deployments');
    const deployments = data.deployments || [];

    if (!deployments.length) {
      tbody.innerHTML = '<tr><td colspan="6">No deployments found. Deploy an app to get started.</td></tr>';
      return;
    }

    tbody.innerHTML = '';

    deployments.forEach((d) => {
      const tr = document.createElement('tr');
      tr.setAttribute('data-deployment-id', d.id);
      const isAIStack = d.app_name === 'tfgrid-ai-stack';

      if (isAIStack) {
        tr.innerHTML = `
          <td><span class="ip-text">${d.id}</span></td>
          <td>${d.app_name || ''}</td>
          <td>${statusBadge(d.status)}</td>
          <td>${formatIPs(d.vm_ip, d.mycelium_ip)}</td>
          <td>${d.contract_id ? `<span class="ip-text">${d.contract_id}</span>` : ''}</td>
          <td style="text-align:right">
            <input type="text" class="project-input" placeholder="project name" />
            <div class="actions-row">
              <button class="btn btn-primary" data-action="create" data-id="${d.id}">Create</button>
              <button class="btn btn-ghost" data-action="run" data-id="${d.id}">Run</button>
              <button class="btn btn-ghost" data-action="publish" data-id="${d.id}">Publish</button>
              <button class="btn btn-ghost" data-action="address" data-id="${d.id}">Address</button>
              <button class="btn btn-ghost" data-action="commands" data-id="${d.id}">Commands</button>
              <button class="btn btn-ghost" data-action="connect" data-id="${d.id}">Connect</button>
            </div>
          </td>
        `;
      } else {
        tr.innerHTML = `
          <td><span class="ip-text">${d.id}</span></td>
          <td>${d.app_name || ''}</td>
          <td>${d.status || ''}</td>
          <td>${formatIPs(d.vm_ip, d.mycelium_ip)}</td>
          <td>${d.contract_id ? `<span class="ip-text">${d.contract_id}</span>` : ''}</td>
          <td style="text-align:right">
            <div class="actions-row">
              <button class="btn btn-ghost" data-action="address" data-id="${d.id}">Address</button>
              <button class="btn btn-ghost" data-action="commands" data-id="${d.id}">Commands</button>
              <button class="btn btn-ghost" data-action="connect" data-id="${d.id}">Connect</button>
            </div>
          </td>
        `;
      }

      const buttons = tr.querySelectorAll('button');
      buttons.forEach((btn) => {
        const action = btn.getAttribute('data-action') || 'address';
        if (action === 'address') {
          btn.addEventListener('click', () => showAddress(d));
        } else if (action === 'commands') {
          btn.addEventListener('click', () => setDeploymentContext(d));
        } else if (action === 'connect') {
          btn.addEventListener('click', () => openShellForDeployment(d));
        } else {
          const input = tr.querySelector('.project-input');
          btn.addEventListener('click', () => handleProjectAction(d, action, input, btn));
        }
      });

      tbody.appendChild(tr);
    });
    updateDeploymentSelectionUI();
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="6">Failed to load deployments: ${err.message}</td></tr>`;
  }
}

async function showAddress(deployment) {
  try {
    showLogPanel(`Deployment ${deployment.id}`, `${deployment.app_name || ''} - address`);
    setLogContent('Loading address information...');

    const data = await fetchJSON(`/api/deployments/${deployment.id}/address`);
    const output = data.output || '';
    setLogContent(output.trim() || 'No output.');
  } catch (err) {
    setLogContent(`Failed to get address: ${err.message}`);
  }
}

async function pollJob(jobId, button, resetLabel) {
  let done = false;
  while (!done) {
    await new Promise((r) => setTimeout(r, 2000));
    try {
      const data = await fetchJSON(`/api/jobs/${jobId}`);
      const job = data;
      const lines = (job.logs || []).join('');
      setLogContent(lines || 'Waiting for output...');

      if (job.status === 'completed' || job.status === 'failed') {
        done = true;
        if (button) {
          button.disabled = false;
          if (resetLabel) button.textContent = resetLabel;
        }
        document.getElementById('log-subtitle').textContent = `Status: ${job.status}${job.deployment_id ? ` • Deployment: ${job.deployment_id}` : ''}`;
        // Refresh deployments list at the end
        loadDeployments();
        loadPreferences();
      }
    } catch (err) {
      setLogContent(`Failed to fetch job: ${err.message}`);
      done = true;
      if (button) {
        button.disabled = false;
        if (resetLabel) button.textContent = resetLabel;
      }
    }
  }
}

async function startDeployment(appName, button) {
  button.disabled = true;
  button.textContent = 'Deploying...';

  showLogPanel(`Deploying ${appName}`, 'Running tfgrid-compose up');
  setLogContent('Starting deployment job...');

  try {
    const res = await fetchJSON('/api/deployments', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ appName }),
    });
    const jobId = res.job_id;
    if (!jobId) throw new Error('Dashboard backend did not return job_id');
    await pollJob(jobId, button, 'Deploy');
  } catch (err) {
    setLogContent(`Failed to start deployment: ${err.message}`);
    button.disabled = false;
    button.textContent = 'Deploy';
  }
}

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('log-close').addEventListener('click', hideLogPanel);
  document.getElementById('refresh-all').addEventListener('click', () => {
    loadApps();
    loadDeployments();
    loadPreferences();
  });

  const clearContextBtn = document.getElementById('commands-context-clear');
  if (clearContextBtn) {
    clearContextBtn.addEventListener('click', () => setDeploymentContext(null));
  }

  const shellCloseBtn = document.getElementById('shell-close');
  if (shellCloseBtn) {
    shellCloseBtn.addEventListener('click', () => {
      closeShellPanel();
    });
  }

  const shellSendBtn = document.getElementById('shell-send');
  if (shellSendBtn) {
    shellSendBtn.addEventListener('click', () => {
      sendShellInput();
    });
  }

  const shellInput = document.getElementById('shell-input');
  if (shellInput) {
    shellInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        sendShellInput();
      }
    });
  }

  loadApps();
  loadDeployments();
  loadCommands();
  loadPreferences();
});
