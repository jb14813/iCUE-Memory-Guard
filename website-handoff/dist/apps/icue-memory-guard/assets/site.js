const toggle = document.querySelector('.nav-toggle');
const nav = document.querySelector('.site-nav');
function closeMenu() {
  toggle?.setAttribute('aria-expanded', 'false');
  toggle?.setAttribute('aria-label', 'Open navigation');
  nav?.classList.remove('is-open');
}
toggle?.addEventListener('click', () => {
  const open = toggle.getAttribute('aria-expanded') !== 'true';
  toggle.setAttribute('aria-expanded', String(open));
  toggle.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
  nav.classList.toggle('is-open', open);
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && toggle?.getAttribute('aria-expanded') === 'true') {
    closeMenu();
    toggle.focus();
  }
});
document.addEventListener('click', event => {
  if (!event.target.closest('.site-header')) closeMenu();
});
nav?.querySelectorAll('a').forEach(link => link.addEventListener('click', closeMenu));
window.matchMedia('(min-width: 801px)').addEventListener('change', closeMenu);
document.querySelector('[data-copy-email]')?.addEventListener('click', async event => {
  const status = document.querySelector('[data-copy-status]');
  try {
    await navigator.clipboard.writeText(event.currentTarget.dataset.copyEmail);
    status.textContent = 'Email address copied.';
  } catch {
    status.textContent = 'Select and copy the email address above.';
  }
});
