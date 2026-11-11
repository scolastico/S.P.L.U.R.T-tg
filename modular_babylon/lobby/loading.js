// One browser document keeps status updates from resetting the viewport.
var lobbyView = '';
var lobbyScroll = {};
var lobbyPending = false;
var lobbyRevision = -1;

function rememberLobbyScroll() {
  if (lobbyView && !lobbyPending) {
    lobbyScroll[lobbyView] = window.pageYOffset || document.documentElement.scrollTop || 0;
  }
}

function showLobbyLoading(name, stage) {
  rememberLobbyScroll();
  lobbyPending = true;
  document.getElementById('loading-world').textContent = name || 'Your world';
  document.getElementById('loading-stage').textContent = stage || 'Working...';
  document.getElementById('browser-content').style.display = 'none';
  document.getElementById('action-loading').style.display = 'block';
  window.scrollTo(0, 0);
}

function beginAction(link) {
  if (lobbyPending) return false;
  showLobbyLoading(link.getAttribute('data-world') || 'Babylon 13',
    link.getAttribute('data-stage') || 'Preparing your request...');
  return true;
}

function renderLobby(encoded) {
  var data = JSON.parse(encoded);
  if (data.revision < lobbyRevision || (lobbyPending && !data.complete)) return;
  rememberLobbyScroll();
  lobbyRevision = data.revision;
  lobbyView = data.view;
  var main = document.getElementById('browser-content');
  if (main.innerHTML !== data.html) main.innerHTML = data.html;
  document.getElementById('action-loading').style.display = 'none';
  main.style.display = 'block';
  lobbyPending = false;
  var position = lobbyScroll[lobbyView] || 0;
  window.scrollTo(0, position);
  setTimeout(function () {
    if (!lobbyPending && lobbyView === data.view && lobbyRevision === data.revision) window.scrollTo(0, position);
  }, 0);
}
