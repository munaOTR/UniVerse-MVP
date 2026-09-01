const SOURCE = 'https://raw.githubusercontent.com/munaOTR/UniVerse-MVP/main/dashboard.html';

function patchDashboard(html) {
  let out = html;

  // Use an iOS-safe auth lock and keep the existing client instance used by the dashboard.
  out = out.replace(
    /window\._supabase\s*=\s*supabase\.createClient\(supabaseUrl,\s*supabaseKey\);/,
    `window._supabase = supabase.createClient(supabaseUrl, supabaseKey, {
            auth: {
                persistSession: true,
                autoRefreshToken: true,
                detectSessionInUrl: true,
                lock: async (_name, _acquireTimeout, fn) => fn()
            }
        });`
  );

  // Make the authenticated state visible to the enhancement modules.
  out = out.replace(
    /currentSessionUser\s*=\s*session\.user;\s*currentUserId\s*=\s*session\.user\.id;/,
    `currentSessionUser = session.user;
            currentUserId = session.user.id;
            window.currentSessionUser = currentSessionUser;
            window.currentUserId = currentUserId;`
  );

  out = out.replace(
    /userUniversity\s*=\s*\(profile\?\.university\s*\|\|\s*metadataUniversity\s*\|\|\s*''\)\.trim\(\);\s*userFullName\s*=\s*\(profile\?\.full_name\s*\|\|\s*metadataFullName\s*\|\|\s*''\)\.trim\(\);/,
    `userUniversity = (profile?.university || metadataUniversity || '').trim();
            userFullName = (profile?.full_name || metadataFullName || '').trim();
            window.userUniversity = userUniversity;
            window.userFullName = userFullName;`
  );

  // Never wait for every external resource before authentication starts.
  out = out.replace(
    /if\s*\(document\.readyState\s*===\s*['"]complete['"]\)\s*init\(\);\s*else\s*window\.addEventListener\(['"]load['"],\s*init,\s*\{\s*once:\s*true\s*\}\);/,
    `if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true });
        else init();`
  );

  // If an older dashboard build still waits on load, explicitly start it as soon as the
  // DOM is ready by calling the same startup path through a guarded synthetic load event.
  const safety = `<script>
(() => {
  const run = () => {
    try {
      if (window._supabase && document.getElementById('userUniDisplay')?.textContent?.trim().toLowerCase() === 'verifying...') {
        window.dispatchEvent(new Event('load'));
      }
    } catch (e) { console.error('UniVerse production boot recovery:', e); }
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => setTimeout(run, 0), { once: true });
  else setTimeout(run, 0);
})();
</script>`;
  if (!out.includes('UniVerse production boot recovery')) out = out.replace('</head>', `${safety}\n</head>`);

  return out;
}

module.exports = async function handler(req, res) {
  try {
    const response = await fetch(SOURCE, { cache: 'no-store' });
    if (!response.ok) throw new Error(`Dashboard source returned ${response.status}`);
    const html = patchDashboard(await response.text());
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store, max-age=0');
    res.status(200).send(html);
  } catch (error) {
    console.error('Dashboard proxy failed:', error);
    res.status(502).send('<!doctype html><html><body style="font-family:system-ui;padding:2rem;background:#05070c;color:white"><h2>UniVerse ICOS is temporarily unavailable</h2><p>Please refresh in a moment.</p></body></html>');
  }
};
