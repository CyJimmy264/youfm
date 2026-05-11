function renderLog(payload) {
  const log = document.getElementById('recent_log');
  const path = document.getElementById('log_path');
  if (!log) return;

  if (path && payload.path) path.textContent = payload.path;
  log.replaceChildren(...renderLogLines(payload.lines || ['No log lines yet']));
  log.scrollTop = log.scrollHeight;
}

function renderLogLines(lines) {
  return lines.flatMap((line, index) => {
    const fragment = document.createDocumentFragment();
    appendColoredLogLine(fragment, line);
    if (index < lines.length - 1) fragment.appendChild(document.createTextNode('\n'));
    return Array.from(fragment.childNodes);
  });
}

function appendColoredLogLine(parent, line) {
  const httpPattern = /^(\[[^\]]+\]\s+\[youfm\]\s+http\s+)(SPOTIFY|LASTFM)\s+(GET|POST|PUT|DELETE|PATCH)\s+(\S+)\s+(\S+)\s+(.*)$/;
  const match = String(line).match(httpPattern);
  if (!match) {
    parent.appendChild(document.createTextNode(line));
    return;
  }

  parent.appendChild(document.createTextNode(match[1]));
  parent.appendChild(logSpan(`provider-${match[2].toLowerCase()}`, match[2].padEnd(7, ' ')));
  parent.appendChild(document.createTextNode(' '));
  parent.appendChild(logSpan('method', match[3].padEnd(6, ' ')));
  parent.appendChild(document.createTextNode(' '));
  parent.appendChild(logSpan(statusClass(match[4]), match[4].padStart(4, ' ')));
  parent.appendChild(document.createTextNode(' '));
  parent.appendChild(logSpan('elapsed', match[5].padStart(7, ' ')));
  parent.appendChild(document.createTextNode(` ${match[6]}`));
}

function logSpan(className, text) {
  const span = document.createElement('span');
  span.className = `log-${className}`;
  span.textContent = text;
  return span;
}

function statusClass(status) {
  const code = Number(status);
  return Number.isFinite(code) && code >= 200 && code < 400 ? 'status-ok' : 'status-error';
}

function renderState(payload) {
  const fields = {
    now_playing: payload.now_playing,
    recommendation_seed: payload.recommendation_seed,
    status_message: payload.status_message,
    device_name: payload.device_name
  };

  Object.entries(fields).forEach(([id, value]) => {
    const element = document.getElementById(id);
    if (element) element.textContent = value;
  });

  renderPlaylists(payload);
}

function renderPlaylists(payload) {
  const select = document.getElementById('playlist_index');
  const button = document.getElementById('use_playlist_button');
  const summary = document.getElementById('seed_playlist_summary');
  if (!select) return;

  const playlists = payload.playlists || [];
  const selectedIndex = String(payload.selected_playlist_index ?? 0);
  const previousValue = select.value;
  const userIsChoosing = document.activeElement === select;
  const playlistSignature = JSON.stringify(
    playlists.map((playlist) => [playlist.index, playlist.label])
  );
  if (select.dataset.playlistSignature !== playlistSignature) {
    select.replaceChildren(
      ...playlists.map((playlist) => {
        const option = document.createElement('option');
        option.value = playlist.index;
        option.textContent = playlist.label;
        return option;
      })
    );
    select.dataset.playlistSignature = playlistSignature;
  }
  const availableValues = playlists.map((playlist) => String(playlist.index));
  if (userIsChoosing && availableValues.includes(previousValue)) {
    select.value = previousValue;
  } else if (availableValues.includes(selectedIndex)) {
    select.value = selectedIndex;
  } else if (availableValues.includes(previousValue)) {
    select.value = previousValue;
  }
  select.disabled = playlists.length === 0;
  if (button) button.disabled = playlists.length === 0;
  if (summary) {
    summary.textContent = `${payload.tracks_title || 'Tracks'} · ${payload.seed_track_count || 0} seed tracks`;
  }
}

async function refreshLog() {
  try {
    const response = await fetch('/log', { headers: { 'Accept': 'application/json' } });
    renderLog(await response.json());
  } catch (error) {
    const log = document.getElementById('recent_log');
    if (log.textContent === 'Loading log...') log.textContent = 'No log lines yet';
  }
}

async function refreshState() {
  try {
    const response = await fetch('/state', { headers: { 'Accept': 'application/json' } });
    renderState(await response.json());
  } catch (error) {}
}

if (window.EventSource) {
  const logEvents = new EventSource('/log/stream');
  const stateEvents = new EventSource('/state/stream');
  logEvents.addEventListener('log', (event) => renderLog(JSON.parse(event.data)));
  stateEvents.addEventListener('state', (event) => renderState(JSON.parse(event.data)));
  logEvents.onerror = () => {
    if (document.getElementById('recent_log')?.textContent === 'Loading log...') refreshLog();
  };
  stateEvents.onerror = () => refreshState();
  window.addEventListener('beforeunload', () => {
    logEvents.close();
    stateEvents.close();
  });
} else {
  refreshLog();
  refreshState();
  setInterval(refreshLog, 1000);
  setInterval(refreshState, 1000);
}

document.querySelectorAll('form[action="/action"]').forEach((form) => {
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const submitter = event.submitter;
    if (submitter) submitter.disabled = true;

    try {
      const response = await fetch(form.action, {
        method: 'POST',
        headers: { 'Accept': 'application/json' },
        body: new FormData(form)
      });
      const payload = await response.json();
      const status = document.getElementById('status_message');
      if (status && payload.status) status.textContent = payload.status;
    } catch (error) {
      const status = document.getElementById('status_message');
      if (status) status.textContent = `Web UI request failed: ${error.message}`;
    } finally {
      if (submitter) submitter.disabled = false;
    }
  });
});
