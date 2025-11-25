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

  // Reset job state when closing the log panel
  jobsState.clear();
  activeJobId = null;
  refreshJobsBar();

  clearJobsFromStorage();

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
let logAutoScroll = true;
let shellAutoScroll = true;

function setLogContent(text) {
  const el = document.getElementById('log-content');
  if (!el) return;
  el.innerHTML = ansiToHtml(text || '');
  if (logAutoScroll) {
    el.scrollTop = el.scrollHeight;
  }
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
  if (shellAutoScroll) {
    el.scrollTop = el.scrollHeight;
  }
}

const jobsState = new Map();
let activeJobId = null;
let jobCounter = 0;

const JOBS_STORAGE_KEY = 'tfgrid-dashboard-jobs-v1';

function persistJobsToStorage() {
  try {
    const payload = {
      activeJobId,
      jobs: Array.from(jobsState.values()).map((job) => ({
        id: job.id,
        index: job.index,
        title: job.title || 'Job',
        subtitle: job.subtitle || '',
        status: job.status || 'running',
        deployment_id: job.deployment_id || null,
      })),
    };
    window.localStorage.setItem(JOBS_STORAGE_KEY, JSON.stringify(payload));
  } catch (e) {
    // Ignore storage errors
  }
}

function loadJobsFromStorage() {
  try {
    const raw = window.localStorage.getItem(JOBS_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || !Array.isArray(parsed.jobs)) return null;
    return parsed;
  } catch (e) {
    return null;
  }
}

function clearJobsFromStorage() {
  try {
    window.localStorage.removeItem(JOBS_STORAGE_KEY);
  } catch (e) {
    // Ignore storage errors
  }
}

function refreshJobsBar() {
  const bar = document.getElementById('jobs-bar');
  const tabs = document.getElementById('jobs-tabs');
  if (!bar || !tabs) return;

  tabs.innerHTML = '';

  if (!jobsState.size) {
    bar.classList.add('hidden');
    return;
  }

  bar.classList.remove('hidden');

  const jobs = Array.from(jobsState.values()).sort((a, b) => a.index - b.index);

  jobs.forEach((job) => {
    const tab = document.createElement('button');
    tab.type = 'button';
    tab.className = 'job-tab' + (job.id === activeJobId ? ' job-tab-active' : '');
    tab.dataset.jobId = job.id;

    const statusDot = document.createElement('span');
    let statusClass = 'job-status-running';
    if (job.status === 'completed') statusClass = 'job-status-completed';
    else if (job.status === 'failed') statusClass = 'job-status-failed';
    statusDot.className = `job-status-dot ${statusClass}`;
    tab.appendChild(statusDot);

    const indexSpan = document.createElement('span');
    indexSpan.textContent = `#${job.index}`;
    tab.appendChild(indexSpan);

    const labelSpan = document.createElement('span');
    labelSpan.className = 'job-tab-label';
    labelSpan.textContent = job.title || 'Job';
    tab.appendChild(labelSpan);

    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'job-tab-close';
    closeBtn.innerHTML = '×';
    closeBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      closeJob(job.id);
    });
    tab.appendChild(closeBtn);

    tab.addEventListener('click', () => {
      if (activeJobId !== job.id) {
        activeJobId = job.id;
        updateActiveJobView();
        refreshJobsBar();
      }
    });

    tabs.appendChild(tab);
  });
}

function updateActiveJobView() {
  const panel = document.getElementById('log-panel');
  const placeholder = document.getElementById('output-placeholder');
  const bar = document.getElementById('jobs-bar');
  const titleEl = document.getElementById('log-title');
  const subtitleEl = document.getElementById('log-subtitle');

  if (!activeJobId || !jobsState.has(activeJobId)) {
    if (panel) panel.classList.add('hidden');
    if (placeholder) placeholder.classList.remove('hidden');
    if (bar) bar.classList.add('hidden');
    return;
  }

  const job = jobsState.get(activeJobId);

  if (panel) panel.classList.remove('hidden');
  if (placeholder) placeholder.classList.add('hidden');
  if (bar) bar.classList.remove('hidden');

  if (titleEl) titleEl.textContent = job.title || 'Job Output';
  if (subtitleEl) {
    const statusText = job.status
      ? `Status: ${job.status}${job.deployment_id ? ` • Deployment: ${job.deployment_id}` : ''}`
      : '';
    subtitleEl.textContent = job.subtitle ? `${job.subtitle} • ${statusText}` : statusText;
  }

  setLogContent(job.logsText || 'Waiting for output...');
}

function registerJob(jobId, meta) {
  jobCounter += 1;
  jobsState.set(jobId, {
    id: jobId,
    index: jobCounter,
    title: meta.title || 'Job',
    subtitle: meta.subtitle || '',
    status: 'running',
    logsText: meta.initialLog || '',
    deployment_id: null,
  });
  activeJobId = jobId;
  refreshJobsBar();
  updateActiveJobView();

  persistJobsToStorage();
}

function updateJobFromServer(jobId, jobData) {
  if (!jobsState.has(jobId)) return;
  const job = jobsState.get(jobId);
  job.status = jobData.status || job.status || 'running';
  job.deployment_id = jobData.deployment_id || job.deployment_id || null;
  job.logsText = (jobData.logs || []).join('');
  jobsState.set(jobId, job);
  refreshJobsBar();
  if (activeJobId === jobId) {
    updateActiveJobView();
  }

  persistJobsToStorage();
}

function closeJob(jobId) {
  const wasActive = activeJobId === jobId;
  jobsState.delete(jobId);
  if (!jobsState.size) {
    activeJobId = null;
  } else if (wasActive) {
    const remaining = Array.from(jobsState.values()).sort((a, b) => b.index - a.index);
    activeJobId = remaining[0].id;
  }
  refreshJobsBar();
  updateActiveJobView();

  if (!jobsState.size) {
    clearJobsFromStorage();
  } else {
    persistJobsToStorage();
  }
}

async function rehydrateJobsFromStorage() {
  const stored = loadJobsFromStorage();
  if (!stored || !stored.jobs || !stored.jobs.length) return;

  jobsState.clear();
  jobCounter = 0;
  activeJobId = null;

  stored.jobs
    .slice()
    .sort((a, b) => (a.index || 0) - (b.index || 0))
    .forEach((meta) => {
      const idx = meta.index && Number.isFinite(meta.index) ? meta.index : jobCounter + 1;
      if (idx > jobCounter) {
        jobCounter = idx;
      }
      jobsState.set(meta.id, {
        id: meta.id,
        index: idx,
        title: meta.title || 'Job',
        subtitle: meta.subtitle || '',
        status: meta.status || 'running',
        logsText: 'Restoring job output...',
        deployment_id: meta.deployment_id || null,
      });
    });

  if (stored.activeJobId && jobsState.has(stored.activeJobId)) {
    activeJobId = stored.activeJobId;
  } else {
    const remaining = Array.from(jobsState.values()).sort((a, b) => b.index - a.index);
    activeJobId = remaining.length ? remaining[0].id : null;
  }

  refreshJobsBar();
  updateActiveJobView();

  const currentJobs = Array.from(jobsState.values());
  currentJobs.forEach(async (job) => {
    try {
      const data = await fetchJSON(`/api/jobs/${job.id}`);
      updateJobFromServer(job.id, data);
      const status = data.status;
      if (status !== 'completed' && status !== 'failed') {
        pollJob(job.id, null, null);
      }
    } catch (err) {
      if (jobsState.has(job.id)) {
        jobsState.delete(job.id);
        if (activeJobId === job.id) {
          activeJobId = null;
        }
      }
      refreshJobsBar();
      updateActiveJobView();
      persistJobsToStorage();
    }
  });
}

function isDeploymentScopedCommand(cmd) {
  const id = cmd && (cmd.id || cmd.command);
  return id === 'status:app' || id === 'logs:app' || id === 'ssh' || id === 'exec' || id === 'address';
}

function getInitialStateForCommand(cmd) {
  const initial = { args: {}, flags: {} };
  const id = cmd && (cmd.id || cmd.command);

  // Global presets that do not depend on deployment context
  if (id === 'delete') {
    initial.args.subcommand = 'delete';
  }

  if (!deploymentContext) return initial;

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
function renderAppActionsPanel() {
  const panel = document.getElementById('app-actions-panel');
  if (!panel) return;

  if (!deploymentContext) {
    panel.innerHTML = '<div class="card"><div class="card-body">Select a deployment in the table below to see app-specific actions.</div></div>';
    return;
  }

  const appName = deploymentContext.app_name || '';

  if (appName === 'tfgrid-ai-stack') {
    renderAiStackActions(panel);
  } else if (appName === 'tfgrid-ai-agent') {
    panel.innerHTML = '<div class="card"><div class="card-header"><h3 class="card-title">AI Agent</h3></div><div class="card-body"><p>Use the CLI Commands panel and the selected deployment context to run tfgrid-compose commands for this AI agent (for example: status, logs, ssh, exec).</p></div></div>';
  } else if (appName === 'tfgrid-gitea') {
    panel.innerHTML = '<div class="card"><div class="card-header"><h3 class="card-title">Gitea Git Hosting</h3></div><div class="card-body"><p>Use the Address button in the deployments table to open the Gitea web UI for this deployment. You can also use CLI Commands with this deployment context for advanced operations.</p></div></div>';
  } else {
    panel.innerHTML = '<div class="card"><div class="card-body">No app-specific actions are defined for this application.</div></div>';
  }
}

function setDeploymentContext(deployment) {
  deploymentContext = deployment || null;
  updateCommandsContextUI();
  renderAppActionsPanel();
}

function buildAiStackCreatePreview(body) {
  const parts = ['tfgrid-compose', 'create', '--project', body.projectName || '<project>'];
  if (body.time) parts.push(`--time=${body.time}`);
  if (body.prompt) parts.push(`--prompt=${body.prompt}`);
  if (body.template) parts.push(`--template=${body.template}`);
  if (body.git_name) parts.push(`--git-name=${body.git_name}`);
  if (body.git_email) parts.push(`--git-email=${body.git_email}`);
  if (body.auto_run) parts.push('--run=yes');
  if (body.auto_publish) parts.push('--publish=yes');
  if (body.non_interactive !== false) parts.push('--non-interactive');
  return parts.join(' ');
}

function buildAiStackRunPreview(body) {
  const parts = ['tfgrid-compose', 'run', body.projectName || '<project>'];
  if (body.wait) parts.push('--wait');
  return parts.join(' ');
}

function buildAiStackPublishPreview(body) {
  const parts = ['tfgrid-compose', 'publish', body.projectName || '<project>'];
  if (body.force) parts.push('--force');
  return parts.join(' ');
}

function renderAiStackActions(panel) {
  const deployment = deploymentContext;
  if (!deployment) {
    panel.innerHTML = '<div class="card"><div class="card-body">Select a tfgrid-ai-stack deployment to manage AI projects.</div></div>';
    return;
  }

  panel.innerHTML = `
    <div class="card">
      <div class="card-header">
        <h3 class="card-title">AI Projects (tfgrid-ai-stack)</h3>
        <p class="card-subtitle">Create, run, and publish AI projects on the selected deployment.</p>
      </div>
      <div class="card-body">
        <div class="ai-stack-auth-banner">
          <div id="ai-stack-auth-text">Checking Qwen authentication...</div>
          <div class="ai-stack-auth-actions">
            <button type="button" id="ai-stack-login-btn" class="btn btn-ghost btn-small">Login to Qwen</button>
            <button type="button" id="ai-stack-auth-refresh" class="btn btn-ghost btn-small">Check again</button>
          </div>
        </div>

        <div class="form-section">
          <h4>Create Project</h4>
          <form id="ai-stack-create-form">
            <div class="form-field">
              <label>
                <span>Project name *</span>
                <input type="text" name="project-name" placeholder="my-project" />
              </label>
            </div>
            <div class="form-field">
              <label>
                <span>Time / budget (optional)</span>
                <input type="text" name="time" placeholder="30m, 2h, etc." />
              </label>
            </div>
            <div class="form-field">
              <label>
                <span>Prompt (optional)</span>
                <textarea name="prompt" rows="3" placeholder="High-level description of the project."></textarea>
              </label>
            </div>
            <div class="form-field">
              <label>
                <span>Template (optional)</span>
                <input type="text" name="template" placeholder="template name" />
              </label>
            </div>
            <div class="form-field">
              <label>
                <span>Git name (optional)</span>
                <input type="text" name="git-name" placeholder="Override git user.name" />
              </label>
            </div>
            <div class="form-field">
              <label>
                <span>Git email (optional)</span>
                <input type="text" name="git-email" placeholder="Override git user.email" />
              </label>
            </div>
            <div class="form-section">
              <div class="form-field">
                <label class="checkbox-label">
                  <input type="checkbox" name="auto-run" />
                  <span>Auto-run after create (--run)</span>
                </label>
              </div>
              <div class="form-field">
                <label class="checkbox-label">
                  <input type="checkbox" name="auto-publish" />
                  <span>Auto-publish after run (--publish)</span>
                </label>
              </div>
              <div class="form-field">
                <label class="checkbox-label">
                  <input type="checkbox" name="non-interactive" checked />
                  <span>Non-interactive mode (--non-interactive)</span>
                </label>
              </div>
            </div>
            <div class="form-actions">
              <button type="submit" class="btn btn-primary">Create project</button>
            </div>
          </form>
        </div>

        <div class="form-section">
          <h4>Run Project</h4>
          <form id="ai-stack-run-form">
            <div class="form-field">
              <label>
                <span>Project name *</span>
                <input type="text" name="project-name-run" placeholder="my-project" />
              </label>
            </div>
            <div class="form-field">
              <label class="checkbox-label">
                <input type="checkbox" name="wait" />
                <span>Wait for completion (--wait)</span>
              </label>
            </div>
            <div class="form-actions">
              <button type="submit" class="btn btn-primary">Run project</button>
            </div>
          </form>
        </div>

        <div class="form-section">
          <h4>Publish Project</h4>
          <form id="ai-stack-publish-form">
            <div class="form-field">
              <label>
                <span>Project name *</span>
                <input type="text" name="project-name-publish" placeholder="my-project" />
              </label>
            </div>
            <div class="form-field">
              <label class="checkbox-label">
                <input type="checkbox" name="force" />
                <span>Force fresh analysis (--force)</span>
              </label>
            </div>
            <div class="form-actions">
              <button type="submit" class="btn btn-primary">Publish project</button>
            </div>
          </form>
        </div>
      </div>
    </div>
  `;

  const createForm = panel.querySelector('#ai-stack-create-form');
  const runForm = panel.querySelector('#ai-stack-run-form');
  const publishForm = panel.querySelector('#ai-stack-publish-form');

  const createButton = createForm?.querySelector('button[type="submit"]') || null;
  const runButton = runForm?.querySelector('button[type="submit"]') || null;
  const publishButton = publishForm?.querySelector('button[type="submit"]') || null;

  const authText = panel.querySelector('#ai-stack-auth-text');
  const loginButton = panel.querySelector('#ai-stack-login-btn');
  const refreshButton = panel.querySelector('#ai-stack-auth-refresh');

  function setProjectButtonsEnabled(enabled) {
    if (createButton) createButton.disabled = !enabled;
    if (runButton) runButton.disabled = !enabled;
    if (publishButton) publishButton.disabled = !enabled;
  }

  async function refreshQwenAuth() {
    if (!authText) return;
    authText.textContent = 'Checking Qwen authentication...';
    setProjectButtonsEnabled(false);

    try {
      const res = await fetchJSON(`/api/deployments/${deployment.id}/qwen-auth`);
      if (res && res.authenticated) {
        authText.textContent = 'Qwen: Connected. You can create, run, and publish projects.';
        setProjectButtonsEnabled(true);
      } else {
        authText.textContent = 'Qwen: Not authenticated. Click "Login to Qwen" to start the OAuth flow, then complete it in your browser.';
        setProjectButtonsEnabled(false);
      }
    } catch (err) {
      authText.textContent = `Failed to check Qwen authentication: ${err.message}`;
      setProjectButtonsEnabled(false);
    }
  }

  if (refreshButton) {
    refreshButton.addEventListener('click', () => {
      refreshQwenAuth();
    });
  }

  if (loginButton) {
    loginButton.addEventListener('click', async () => {
      const deploymentNow = deploymentContext;
      if (!deploymentNow) {
        showLogPanel('No deployment selected', '');
        setLogContent('Select a tfgrid-ai-stack deployment first.');
        return;
      }

      const originalText = loginButton.textContent || 'Login to Qwen';

      showLogPanel('Login to Qwen', `Deployment ${deploymentNow.id} (${deploymentNow.app_name || ''})`);
      setLogContent('Starting tfgrid-compose login --non-interactive... This will print an OAuth URL; open it in your browser and complete the flow.');

      loginButton.disabled = true;
      loginButton.textContent = 'Logging in...';

      try {
        const res = await fetchJSON(`/api/deployments/${deploymentNow.id}/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}),
        });
        const jobId = res.job_id;
        if (!jobId) throw new Error('Dashboard backend did not return job_id');
        registerJob(jobId, {
          title: 'Login to Qwen',
          subtitle: `Deployment ${deploymentNow.id} (${deploymentNow.app_name || ''})`,
          initialLog: 'Starting tfgrid-compose login --non-interactive...',
        });
        await pollJob(jobId, loginButton, originalText);
        await refreshQwenAuth();
      } catch (err) {
        setLogContent(`Failed to start login: ${err.message}`);
        loginButton.disabled = false;
        loginButton.textContent = originalText;
      }
    });
  }

  // Initially disable project actions until we know auth state
  setProjectButtonsEnabled(false);
  refreshQwenAuth();

  if (createForm) {
    createForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const deploymentNow = deploymentContext;
      if (!deploymentNow) {
        showLogPanel('No deployment selected', '');
        setLogContent('Select a tfgrid-ai-stack deployment first.');
        return;
      }

      const submitButton = createForm.querySelector('button[type="submit"]');
      const originalText = submitButton ? submitButton.textContent : '';

      const projectName = (createForm.querySelector('input[name="project-name"]')?.value || '').trim();
      if (!projectName) {
        showLogPanel('Missing project name', `Deployment ${deploymentNow.id}`);
        setLogContent('Please enter a project name before creating.');
        return;
      }

      const time = (createForm.querySelector('input[name="time"]')?.value || '').trim();
      const prompt = (createForm.querySelector('textarea[name="prompt"]')?.value || '').trim();
      const template = (createForm.querySelector('input[name="template"]')?.value || '').trim();
      const gitName = (createForm.querySelector('input[name="git-name"]')?.value || '').trim();
      const gitEmail = (createForm.querySelector('input[name="git-email"]')?.value || '').trim();
      const autoRun = !!createForm.querySelector('input[name="auto-run"]')?.checked;
      const autoPublish = !!createForm.querySelector('input[name="auto-publish"]')?.checked;
      const nonInteractive = createForm.querySelector('input[name="non-interactive"]')?.checked !== false;

      const payload = {
        projectName,
        time,
        prompt,
        template,
        git_name: gitName,
        git_email: gitEmail,
        auto_run: autoRun,
        auto_publish: autoPublish,
        non_interactive: nonInteractive,
      };

      const preview = buildAiStackCreatePreview({
        projectName,
        time,
        prompt,
        template,
        git_name: gitName,
        git_email: gitEmail,
        auto_run: autoRun,
        auto_publish: autoPublish,
        non_interactive: nonInteractive,
      });

      showLogPanel(`Create ${projectName}`, `Deployment ${deploymentNow.id} (${deploymentNow.app_name || ''})`);
      setLogContent(`Running: ${preview}`);

      if (submitButton) {
        submitButton.disabled = true;
        submitButton.textContent = 'Creating...';
      }

      try {
        const res = await fetchJSON(`/api/deployments/${deploymentNow.id}/create`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const jobId = res.job_id;
        if (!jobId) throw new Error('Dashboard backend did not return job_id');
        registerJob(jobId, {
          title: `Create ${projectName}`,
          subtitle: preview,
          initialLog: `Running: ${preview}`,
        });
        pollJob(jobId, submitButton, originalText || 'Create project');
      } catch (err) {
        setLogContent(`Failed to start create: ${err.message}`);
        if (submitButton) {
          submitButton.disabled = false;
          submitButton.textContent = originalText || 'Create project';
        }
      }
    });
  }

  if (runForm) {
    runForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const deploymentNow = deploymentContext;
      if (!deploymentNow) {
        showLogPanel('No deployment selected', '');
        setLogContent('Select a tfgrid-ai-stack deployment first.');
        return;
      }

      const submitButton = runForm.querySelector('button[type="submit"]');
      const originalText = submitButton ? submitButton.textContent : '';

      const projectName = (runForm.querySelector('input[name="project-name-run"]')?.value || '').trim();
      if (!projectName) {
        showLogPanel('Missing project name', `Deployment ${deploymentNow.id}`);
        setLogContent('Please enter a project name before running.');
        return;
      }

      const wait = !!runForm.querySelector('input[name="wait"]')?.checked;

      const payload = {
        projectName,
        wait,
      };

      const preview = buildAiStackRunPreview({ projectName, wait });

      showLogPanel(`Run ${projectName}`, `Deployment ${deploymentNow.id} (${deploymentNow.app_name || ''})`);
      setLogContent(`Running: ${preview}`);

      if (submitButton) {
        submitButton.disabled = true;
        submitButton.textContent = 'Running...';
      }

      try {
        const res = await fetchJSON(`/api/deployments/${deploymentNow.id}/run`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const jobId = res.job_id;
        if (!jobId) throw new Error('Dashboard backend did not return job_id');
        registerJob(jobId, {
          title: `Run ${projectName}`,
          subtitle: preview,
          initialLog: `Running: ${preview}`,
        });
        pollJob(jobId, submitButton, originalText || 'Run project');
      } catch (err) {
        setLogContent(`Failed to start run: ${err.message}`);
        if (submitButton) {
          submitButton.disabled = false;
          submitButton.textContent = originalText || 'Run project';
        }
      }
    });
  }

  if (publishForm) {
    publishForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const deploymentNow = deploymentContext;
      if (!deploymentNow) {
        showLogPanel('No deployment selected', '');
        setLogContent('Select a tfgrid-ai-stack deployment first.');
        return;
      }

      const submitButton = publishForm.querySelector('button[type="submit"]');
      const originalText = submitButton ? submitButton.textContent : '';

      const projectName = (publishForm.querySelector('input[name="project-name-publish"]')?.value || '').trim();
      if (!projectName) {
        showLogPanel('Missing project name', `Deployment ${deploymentNow.id}`);
        setLogContent('Please enter a project name before publishing.');
        return;
      }

      const force = !!publishForm.querySelector('input[name="force"]')?.checked;

      const payload = {
        projectName,
        force,
      };

      const preview = buildAiStackPublishPreview({ projectName, force });

      showLogPanel(`Publish ${projectName}`, `Deployment ${deploymentNow.id} (${deploymentNow.app_name || ''})`);
      setLogContent(`Running: ${preview}`);

      if (submitButton) {
        submitButton.disabled = true;
        submitButton.textContent = 'Publishing...';
      }

      try {
        const res = await fetchJSON(`/api/deployments/${deploymentNow.id}/publish`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const jobId = res.job_id;
        if (!jobId) throw new Error('Dashboard backend did not return job_id');
        registerJob(jobId, {
          title: `Publish ${projectName}`,
          subtitle: preview,
          initialLog: `Running: ${preview}`,
        });
        pollJob(jobId, submitButton, originalText || 'Publish project');
      } catch (err) {
        setLogContent(`Failed to start publish: ${err.message}`);
        if (submitButton) {
          submitButton.disabled = false;
          submitButton.textContent = originalText || 'Publish project';
        }
      }
    });
  }
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
          openCommandWithInitial(cmd.id || cmd.command, initial);
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
    let val = el.value.trim();
    if (!val) return;
    
    // Handle comma-separated values (e.g., contract IDs) - convert to space-separated
    if (arg.name === 'ids' && val.includes(',')) {
      val = val.split(',').map(v => v.trim()).filter(v => v).join(' ');
    }
    
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

  const isDeleteCommand = cmd.id === 'delete' || cmd.command === 'contracts';

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

  if (isDeleteCommand) {
    html += `
      <p class="command-warning">
        Using <code>--all</code> will delete all contracts associated with your mnemonic. This cannot be undone.
      </p>
      <div class="form-section" id="contracts-picker-section">
        <h4>Available Contracts</h4>
        <p class="contracts-help-text">Select contracts to delete. Selected IDs are added to the Contract ID(s) field above.</p>
        <div class="contracts-picker-body">
          <div class="contracts-loading">Loading contracts...</div>
        </div>
      </div>
    `;
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

  // When showing a command form, collapse the empty output placeholder
  const outputPlaceholder = document.getElementById('output-placeholder');
  if (outputPlaceholder) {
    outputPlaceholder.classList.add('hidden');
  }

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

    // Highlight dangerous delete-all usage when applicable
    if (isDeleteCommand) {
      const allCheckbox = form.querySelector('input[name="flag-all"]');
      const yesCheckbox = form.querySelector('input[name="flag-yes"]');
      const warningEl = form.querySelector('.command-warning');
      if (allCheckbox && warningEl) {
        const syncWarning = () => {
          if (allCheckbox.checked) {
            warningEl.classList.add('active');
          } else {
            warningEl.classList.remove('active');
          }
          updatePreview();
        };
        allCheckbox.addEventListener('change', syncWarning);
        syncWarning();
      }

      // Dashboard cannot handle interactive yes/no prompts, so always force --yes
      if (yesCheckbox) {
        yesCheckbox.checked = true;
        yesCheckbox.disabled = true; // Prevent unchecking from dashboard
        updatePreview();
      }

      const contractsSection = document.getElementById('contracts-picker-section');
      const idsInput = form.querySelector('input[name="arg-ids"]');
      if (contractsSection && idsInput) {
        const pickerBody = contractsSection.querySelector('.contracts-picker-body');
        if (pickerBody) {
          (async () => {
            try {
              const data = await fetchJSON('/api/contracts');
              const nodeContracts = data.node_contracts || [];
              const nameContracts = data.name_contracts || [];

              if (!nodeContracts.length && !nameContracts.length) {
                pickerBody.innerHTML = '<div class="contracts-empty">No active contracts found.</div>';
                return;
              }

              let htmlPicker = '';

              if (nodeContracts.length) {
                htmlPicker += '<div class="contracts-group"><h5 class="contracts-group-title">Node contracts</h5><div class="contracts-list">';
                nodeContracts.forEach((c) => {
                  const id = c.id;
                  const label = c.raw || `ID ${id}`;
                  htmlPicker += `
                    <label class="contracts-item">
                      <input type="checkbox" class="contracts-checkbox" data-contract-id="${id}" />
                      <span class="contracts-label">
                        <span class="contracts-id">#${id}</span>
                        <span class="contracts-meta">${escapeHtml(label)}</span>
                      </span>
                    </label>
                  `;
                });
                htmlPicker += '</div></div>';
              }

              if (nameContracts.length) {
                htmlPicker += '<div class="contracts-group"><h5 class="contracts-group-title">Name contracts</h5><div class="contracts-list">';
                nameContracts.forEach((c) => {
                  const id = c.id;
                  const name = c.name || '';
                  const label = name ? `${id} ${name}` : id;
                  htmlPicker += `
                    <label class="contracts-item">
                      <input type="checkbox" class="contracts-checkbox" data-contract-id="${id}" />
                      <span class="contracts-label">
                        <span class="contracts-id">#${id}</span>
                        <span class="contracts-meta">${escapeHtml(label)}</span>
                      </span>
                    </label>
                  `;
                });
                htmlPicker += '</div></div>';
              }

              pickerBody.innerHTML = htmlPicker;

              const checkboxes = pickerBody.querySelectorAll('.contracts-checkbox');

              const syncIdsFromCheckboxes = () => {
                const existing = (idsInput.value || '').trim();
                const tokens = existing ? existing.split(/[\s,]+/).filter(Boolean) : [];
                const set = new Set(tokens);

                checkboxes.forEach((cb) => {
                  const cid = cb.getAttribute('data-contract-id');
                  if (!cid) return;
                  if (cb.checked) {
                    set.add(cid);
                  } else {
                    set.delete(cid);
                  }
                });

                idsInput.value = Array.from(set).join(' ');
                updatePreview();
              };

              checkboxes.forEach((cb) => {
                cb.addEventListener('change', syncIdsFromCheckboxes);
              });
            } catch (err) {
              pickerBody.innerHTML = `<div class="contracts-error">Failed to load contracts: ${escapeHtml(err.message || String(err))}</div>`;
            }
          })();
        }
      }
    }
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
        registerJob(jobId, {
          title: cmd.label || cmd.command,
          subtitle: preview,
          initialLog: 'Starting command job...',
        });
        pollJob(jobId, submitButton, originalText || 'Run Command');
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

async function openCommandWithInitial(commandId, initial) {
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

  const initialState = initial || { args: {}, flags: {} };
  const hasArgs = Array.isArray(cmd.args) && cmd.args.length > 0;
  const hasFlags = Array.isArray(cmd.flags) && cmd.flags.length > 0;

  // If the command has no arguments or flags, treat it as a one-click action and run it immediately.
  if (!hasArgs && !hasFlags) {
    const preview = `tfgrid-compose ${cmd.command}`;
    showLogPanel(cmd.label || cmd.command, preview);
    setLogContent('Starting command job...');

    try {
      const res = await fetchJSON('/api/commands/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          commandId: cmd.id || cmd.command,
          args: initialState.args || {},
          flags: initialState.flags || {},
        }),
      });
      const jobId = res.job_id;
      if (!jobId) throw new Error('Dashboard backend did not return job_id');
      registerJob(jobId, {
        title: cmd.label || cmd.command,
        subtitle: preview,
        initialLog: 'Starting command job...',
      });
      pollJob(jobId, null, null);
    } catch (err) {
      showLogPanel('Command failed to start', cmd.label || cmd.command);
      setLogContent(`Failed to start command: ${err.message}`);
    }
    return;
  }

  renderCommandDetail(cmd, initialState);
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
    let net = null;
    try {
      net = await fetchJSON('/api/network-settings');
    } catch (e) {
      // network settings are optional; ignore failures
      net = null;
    }
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

    const maxCpu = prefs.max_cpu_usage != null ? `${prefs.max_cpu_usage}%` : 'not set';
    const maxDisk = prefs.max_disk_usage != null ? `${prefs.max_disk_usage}%` : 'not set';
    const minUptime = prefs.min_uptime_days != null ? `${prefs.min_uptime_days} days` : 'not set';

    const netPref = net && net.preference ? net.preference : 'wireguard';
    const netMode = net && net.mode ? net.mode : 'wireguard-only';

    thEl.innerHTML = `
      <div class="card-body">
        <h3>Global thresholds & network</h3>
        <p><strong>Max CPU Usage:</strong> ${maxCpu}</p>
        <p><strong>Max Disk Usage:</strong> ${maxDisk}</p>
        <p><strong>Min Uptime:</strong> ${minUptime}</p>
        <p><strong>Access Preference:</strong> ${escapeHtml(netPref)}</p>
        <p><strong>Provisioning Mode:</strong> ${escapeHtml(netMode)}</p>
        <p class="preferences-note">Thresholds and network settings are applied by tfgrid-compose during node selection and network provisioning.</p>
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
    registerJob(jobId, {
      title: `${actionLabel} ${projectName}`,
      subtitle: `Deployment ${deployment.id} (${deployment.app_name || ''})`,
      initialLog: `Starting tfgrid-compose ${action} ${projectName}...`,
    });
    pollJob(jobId, button, originalText);
  } catch (err) {
    setLogContent(`Failed to start ${action}: ${err.message}`);
    button.disabled = false;
    button.textContent = originalText;
  }
}

async function loadDeployments() {
  const tbody = document.getElementById('deployments-body');
  if (!tbody) return;

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
            <div class="actions-row">
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
        }
      });

      tbody.appendChild(tr);
    });

    updateDeploymentSelectionUI();

    // Auto-select a sensible default deployment when none is selected yet.
    if (!deploymentContext && deployments.length) {
      let preferred = null;
      deployments.forEach((dep) => {
        if (dep.app_name === 'tfgrid-ai-stack') {
          preferred = dep; // last tfgrid-ai-stack wins
        }
      });
      if (!preferred) {
        preferred = deployments[deployments.length - 1];
      }
      if (preferred) {
        setDeploymentContext(preferred);
      }
    }
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="6">Failed to load deployments: ${err.message}</td></tr>`;
  }
}

async function runDirectCli() {
  const input = document.getElementById('direct-cli-input');
  const button = document.getElementById('direct-cli-run');
  if (!input || !button) return;

  const line = (input.value || '').trim();
  if (!line) {
    showLogPanel('Direct tfgrid-compose', '');
    setLogContent('Enter a command to run, for example: "up tfgrid-ai-agent".');
    return;
  }

  showLogPanel('Direct tfgrid-compose', `tfgrid-compose ${line}`);
  setLogContent('Starting direct command job...');

  const originalText = button.textContent || 'Run';
  button.disabled = true;
  button.textContent = 'Running...';

  try {
    const res = await fetchJSON('/api/commands/run-direct', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ line }),
    });
    const jobId = res.job_id;
    if (!jobId) throw new Error('Dashboard backend did not return job_id');
    registerJob(jobId, {
      title: 'Direct tfgrid-compose',
      subtitle: `tfgrid-compose ${line}`,
      initialLog: 'Starting direct command job...',
    });
    pollJob(jobId, button, originalText);
  } catch (err) {
    setLogContent(`Failed to start direct command: ${err.message}`);
    button.disabled = false;
    button.textContent = originalText;
  }
}

async function pollJob(jobId, button, resetLabel) {
  let done = false;
  while (!done && jobsState.has(jobId)) {
    await new Promise((r) => setTimeout(r, 2000));
    try {
      const data = await fetchJSON(`/api/jobs/${jobId}`);
      updateJobFromServer(jobId, data);
      const status = data.status;
      if (status === 'completed' || status === 'failed') {
        done = true;
        if (button) {
          button.disabled = false;
          if (resetLabel) button.textContent = resetLabel;
        }
        loadDeployments();
        loadPreferences();
      }
    } catch (err) {
      updateJobFromServer(jobId, {
        status: 'failed',
        logs: [`Failed to fetch job: ${err.message}`],
      });
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
    registerJob(jobId, {
      title: `Deploying ${appName}`,
      subtitle: 'Running tfgrid-compose up',
      initialLog: 'Starting deployment job...',
    });
    pollJob(jobId, button, 'Deploy');
  } catch (err) {
    setLogContent(`Failed to start deployment: ${err.message}`);
    button.disabled = false;
    button.textContent = 'Deploy';
  }
}

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('log-close').addEventListener('click', hideLogPanel);

  const logContent = document.getElementById('log-content');
  if (logContent) {
    logContent.addEventListener('scroll', () => {
      const nearBottom =
        logContent.scrollHeight - (logContent.scrollTop + logContent.clientHeight) < 20;
      logAutoScroll = nearBottom;
    });
  }

  const shellContent = document.getElementById('shell-content');
  if (shellContent) {
    shellContent.addEventListener('scroll', () => {
      const nearBottom =
        shellContent.scrollHeight - (shellContent.scrollTop + shellContent.clientHeight) < 20;
      shellAutoScroll = nearBottom;
    });
  }

  document.getElementById('refresh-all').addEventListener('click', () => {
    loadApps();
    loadDeployments();
    loadPreferences();
  });

  const closeDashboardBtn = document.getElementById('close-dashboard');
  if (closeDashboardBtn) {
    closeDashboardBtn.addEventListener('click', () => {
      // Attempt to close the window (may be ignored by some browsers
      // if the window was not opened by script, but is useful in kiosk mode).
      window.close();
    });
  }

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

  const directInput = document.getElementById('direct-cli-input');
  const directRun = document.getElementById('direct-cli-run');
  if (directRun) {
    directRun.addEventListener('click', () => {
      runDirectCli();
    });
  }
  if (directInput) {
    directInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        runDirectCli();
      }
    });
  }

  const advancedToggle = document.getElementById('toggle-advanced-cli');
  const directSection = document.querySelector('.direct-cli');
  if (advancedToggle && directSection) {
    const updateLabel = () => {
      const isHidden = directSection.classList.contains('hidden');
      advancedToggle.textContent = isHidden ? 'Open Advanced CLI' : 'Hide Advanced CLI';
    };

    advancedToggle.addEventListener('click', () => {
      directSection.classList.toggle('hidden');
      updateLabel();
    });

    advancedToggle.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        directSection.classList.toggle('hidden');
        updateLabel();
      }
    });

    updateLabel();
  }

  rehydrateJobsFromStorage();

  loadApps();
  loadDeployments();
  loadCommands();
  loadPreferences();
  renderAppActionsPanel();
});
