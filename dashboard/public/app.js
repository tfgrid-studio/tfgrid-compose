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
  const titleEl = document.getElementById('log-title');
  const subtitleEl = document.getElementById('log-subtitle');
  titleEl.textContent = title;
  subtitleEl.textContent = subtitle || '';
  panel.classList.remove('hidden');
}

function hideLogPanel() {
  document.getElementById('log-panel').classList.add('hidden');
}

function setLogContent(text) {
  document.getElementById('log-content').textContent = text;
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
          <button class="btn btn-primary" data-app="${app.name}">Deploy</button>
        </div>
      `;

      const btn = card.querySelector('button');
      btn.addEventListener('click', () => startDeployment(app.name, btn));

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
            </div>
          </td>
        `;
      } else {
        tr.innerHTML = `
          <td><span class="ip-text">${d.id}</span></td>
          <td>${d.app_name || ''}</td>
          <td>${statusBadge(d.status)}</td>
          <td>${formatIPs(d.vm_ip, d.mycelium_ip)}</td>
          <td>${d.contract_id ? `<span class="ip-text">${d.contract_id}</span>` : ''}</td>
          <td style="text-align:right">
            <button class="btn btn-ghost" data-action="address" data-id="${d.id}">Address</button>
          </td>
        `;
      }

      const buttons = tr.querySelectorAll('button');
      buttons.forEach((btn) => {
        const action = btn.getAttribute('data-action') || 'address';
        if (action === 'address') {
          btn.addEventListener('click', () => showAddress(d));
        } else {
          const input = tr.querySelector('.project-input');
          btn.addEventListener('click', () => handleProjectAction(d, action, input, btn));
        }
      });

      tbody.appendChild(tr);
    });
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
  });

  loadApps();
  loadDeployments();
});
