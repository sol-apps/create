/* pb-auth.js — sign-in for {{SLUG}}, the same one every owner app uses.
 *
 * One login for all of the owner's apps: admin@solhann.net and the shared password set on
 * prod with `sudo owner-password`, which is also what this app's dashboard (/_/) takes.
 * Signing in makes this browser this app's PocketBase superuser, so it can do anything
 * the dashboard can. A collection whose rule is left empty (locked) is the owner's alone;
 * open a rule only for what visitors may do without signing in.
 *
 *   PBAuth.getClient()        PocketBase client (same origin), signed in once the owner is
 *   PBAuth.signIn(password)   promise; the email is fixed
 *   PBAuth.signOut()
 *   PBAuth.isSignedIn()
 *   PBAuth.onChange(fn)       fn(isSignedIn) whenever that changes
 */
const PBAuth = (() => {
  const EMAIL = 'admin@solhann.net';
  // Same origin: Caddy fronts this app's own PocketBase, so no CORS.
  const client = new PocketBase(location.origin);
  const listeners = [];
  const signedIn = () => client.authStore.isValid && client.authStore.isSuperuser;
  client.authStore.onChange(() => listeners.forEach((fn) => fn(signedIn())));

  return {
    getClient: () => client,
    signIn: (password) => client.collection('_superusers').authWithPassword(EMAIL, password),
    signOut: () => client.authStore.clear(),
    isSignedIn: signedIn,
    onChange: (fn) => { listeners.push(fn); },
  };
})();
