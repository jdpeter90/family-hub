/* Family Hub v3 - shared browser client (no service role secrets). */
(function (global) {
  'use strict';
  const DEFAULT_API = 'https://dyzdyqllmfoltiqkfvxm.supabase.co';
  // Publishable keys are intended for browsers; the database must enforce RLS.
  const DEFAULT_KEY = 'sb_publishable__zmbFmdUZTDonhyhkeWgsQ_urpHbmVt';
  function localToday() {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/Chicago', year: 'numeric', month: '2-digit', day: '2-digit'
    }).formatToParts(new Date());
    const get = type => parts.find(p => p.type === type).value;
    return get('year') + '-' + get('month') + '-' + get('day');
  }
  function dayOfWeek(isoDate) {
    return new Date(isoDate + 'T12:00:00Z').getUTCDay();
  }
  function client(storageKey, config) {
    config = config || {};
    const API = config.api || DEFAULT_API;
    const KEY = config.publishableKey || DEFAULT_KEY;
    if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(API)) {
      throw new Error('Invalid Supabase API origin');
    }
    let session = null;
    try { session = JSON.parse(sessionStorage.getItem(storageKey) || 'null'); } catch (_) { }
    function save(s) {
      session = {
        access_token: s.access_token,
        refresh_token: s.refresh_token,
        expires_at: Date.now() + (s.expires_in || 3600) * 1000
      };
      sessionStorage.setItem(storageKey, JSON.stringify(session));
    }
    async function send(path, options) {
      options = options || {};
      const headers = Object.assign({ apikey: KEY, 'Content-Type': 'application/json' }, options.headers || {});
      if (!options.noAuth && session) headers.Authorization = 'Bearer ' + session.access_token;
      const response = await fetch(API + path, {
        method: options.method || 'GET',
        headers: headers,
        body: options.body === undefined ? undefined : JSON.stringify(options.body)
      });
      const txt = await response.text();
      let data;
      try { data = txt ? JSON.parse(txt) : null; } catch (_) { data = null; }
      if (!response.ok) throw new Error((data && (data.message || data.error_description || data.msg || data.error)) || 'HTTP ' + response.status);
      return data;
    }
    async function ensureSession() {
      if (!session) throw new Error('Please sign in.');
      if (session.expires_at > Date.now() + 60000) return;
      try {
        const r = await send('/auth/v1/token?grant_type=refresh_token', {
          method: 'POST', noAuth: true, body: { refresh_token: session.refresh_token }
        });
        save(r);
      } catch (e) {
        signOut();
        throw new Error('Your session expired. Please sign in again.');
      }
    }
    async function call(path, options) {
      await ensureSession();
      return send(path, options);
    }
    async function signIn(email, password) {
      const r = await send('/auth/v1/token?grant_type=password', {
        method: 'POST', noAuth: true,
        body: { email: email.trim(), password: password }
      });
      save(r);
    }
    function signOut() {
      session = null;
      sessionStorage.removeItem(storageKey);
    }
    async function membership(requiredRole) {
      const user = await call('/auth/v1/user');
      if (!user || !user.id) throw new Error('Authentication failed.');
      const rows = await call('/rest/v1/family_members?select=family_id,role&user_id=eq.' +
        encodeURIComponent(user.id) + '&limit=2');
      if (!rows || rows.length !== 1 || rows[0].role !== requiredRole) {
        throw new Error('This account is not authorized for the ' +
          (requiredRole === 'tablet' ? 'children’s tablet' : 'parent dashboard') + '.');
      }
      return { familyId: rows[0].family_id, userId: user.id };
    }
    function list(table, familyId, extra) {
      return call('/rest/v1/' + table + '?select=*&family_id=eq.' + encodeURIComponent(familyId) +
        (extra || ''));
    }
    function rpc(name, args) {
      return call('/rest/v1/rpc/' + name, {
        method: 'POST', body: args, headers: { Prefer: 'return=representation' }
      });
    }
    function insert(table, body) {
      return call('/rest/v1/' + table, { method: 'POST', body: body, headers: { Prefer: 'return=minimal' } });
    }
    function patch(table, id, familyId, body) {
      return call('/rest/v1/' + table + '?id=eq.' + encodeURIComponent(id) +
        '&family_id=eq.' + encodeURIComponent(familyId), {
        method: 'PATCH', body: body, headers: { Prefer: 'return=minimal' }
      });
    }
    return { signIn, signOut, membership, list, rpc, insert, patch, ensureSession };
  }
  global.FamilyHubV3 = { client, localToday, dayOfWeek };
})(window);
