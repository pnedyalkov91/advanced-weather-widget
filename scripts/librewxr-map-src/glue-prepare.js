// ==========================================================================
// Glue script 1b: animation frames for a hidden page. Chromium gives a page
// that is not on screen no animation frames, and MapLibre waits for one
// before it even reads its style: the radar kept loaded behind a closed popup
// loads nothing. While a preparation runs and the page is hidden, frames come
// from here instead, GAP ms apart at most; otherwise from the browser. A
// frame asked of the browser before the page hid is taken back, since the map
// asks once and waits. A hidden page also follows the new radar images.
// Loadable under Node for tests.
// ==========================================================================
var WidgetPrepare = (function () {
  'use strict';

  /** Least time between two frames given to a hidden page, in ms. */
  var GAP = 50;

  /** A preparation that never settles stops after this, in ms. */
  var LIMIT = 60000;

  /** How often a hidden page has the viewer look for new radar images, in ms. */
  var REFRESH = 5 * 60 * 1000;

  /** Takes over win.requestAnimationFrame and cancelAnimationFrame. A page
      hidden from the start prepares at once. With `watch` ({ latest: a
      promise of the latest radar image time, reload: has the viewer reload
      its list }), a hidden page follows the new images. Returns { begin,
      end, preparing }. */
  function create(win, doc, watch) {
    var nativeRequest = win.requestAnimationFrame.bind(win);
    var nativeCancel = win.cancelAnimationFrame.bind(win);
    var calls = new Map(), nextId = 1, active = false, since = 0;
    var scheduled = false, last = -Infinity;
    var channel = new win.MessageChannel();

    function now() { return win.performance.now(); }
    function hidden() { return doc.visibilityState === 'hidden'; }

    function toBrowser(id, call) {
      call.nativeId = nativeRequest(function (t) {
        calls.delete(id);
        call.callback(t);
      });
    }

    function flush() {
      scheduled = false;
      if (!active || !hidden()) return;
      if (now() - since >= LIMIT) { active = false; return; }
      last = now();
      var due = [];
      calls.forEach(function (call, id) { if (call.nativeId === null) due.push([id, call]); });
      due.forEach(function (entry) {
        calls.delete(entry[0]);
        try {
          entry[1].callback(last);
        } catch (err) {
          win.setTimeout(function () { throw err; }, 0);
        }
      });
    }
    channel.port1.onmessage = flush;

    function schedule() {
      if (scheduled || !active || !hidden()) return;
      var held = false;
      calls.forEach(function (call) { if (call.nativeId === null) held = true; });
      if (!held) return;
      scheduled = true;
      var wait = GAP - (now() - last);
      if (wait <= 0) channel.port2.postMessage(0);
      else win.setTimeout(function () { channel.port2.postMessage(0); }, wait);
    }

    win.requestAnimationFrame = function (callback) {
      var id = nextId++, call = { callback: callback, nativeId: null };
      calls.set(id, call);
      if (hidden()) schedule();
      else toBrowser(id, call);
      return id;
    };

    win.cancelAnimationFrame = function (id) {
      var call = calls.get(id);
      if (!call) return;
      calls.delete(id);
      if (call.nativeId !== null) nativeCancel(call.nativeId);
    };

    doc.addEventListener('visibilitychange', function () {
      calls.forEach(function (call, id) {
        if (hidden() && call.nativeId !== null) {
          nativeCancel(call.nativeId);
          call.nativeId = null;
        } else if (!hidden() && call.nativeId === null) {
          toBrowser(id, call);
        }
      });
      schedule();
    });

    // The viewer skips its catalog refresh while the page is hidden, and when
    // its list grows it keeps the image it shows: the image prepared at login
    // would be hours old at opening. Hidden, the latest image time is read
    // here every REFRESH ms; a newer one has the viewer reload its list,
    // which puts it on the latest image, as at load.
    if (watch) {
      var seen = null;
      var check = function () {
        watch.latest().then(function (t) {
          if (t == null) return;
          if (seen !== null && t > seen) watch.reload();
          if (seen === null || t > seen) seen = t;
        }, function () {});
      };
      check();
      win.setInterval(function () { if (hidden()) check(); }, REFRESH);
    }

    var api = {
      /** Starts (or restarts) a preparation: a hidden page gets frames. */
      begin: function () { active = true; since = now(); schedule(); },
      /** Ends it: a hidden page waits for the browser again. */
      end: function () { active = false; },
      /** Whether the hidden page gets frames from here right now. */
      preparing: function () { return active && hidden() && now() - since < LIMIT; }
    };
    if (hidden()) api.begin();
    return api;
  }

  return { GAP: GAP, LIMIT: LIMIT, REFRESH: REFRESH, create: create };
})();

if (typeof module !== 'undefined' && module.exports) { module.exports = WidgetPrepare; }
