// The code travels in the URL path (/invite/ABC123). Pull it out, display it, and aim the
// deep-link button at the custom scheme the app already registers (couplesync://invite/…).
// External (not inline) so the CSP in _headers can forbid inline script — see script-src there.
(function () {
  const m = window.location.pathname.match(/^\/invite\/([A-HJ-NP-Za-hj-np-z2-9]{6})\/?$/);
  const codeEl = document.getElementById('invite-code');
  const openBtn = document.getElementById('open-app');
  if (m) {
    const code = m[1].toUpperCase();
    codeEl.textContent = code;
    openBtn.href = 'couplesync://invite/' + code;
  } else {
    codeEl.textContent = 'no code';
    openBtn.style.display = 'none';
  }
})();
