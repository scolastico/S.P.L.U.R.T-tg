function beginJoin(link) {
  var main = document.getElementById('browser-content');
  var loading = document.getElementById('join-loading');
  var name = document.getElementById('loading-world');
  if (name) name.textContent = link.getAttribute('data-world') || 'your world';
  if (main) main.style.display = 'none';
  if (loading) { loading.style.display = 'block'; loading.setAttribute('aria-busy', 'true'); }
  return true;
}
