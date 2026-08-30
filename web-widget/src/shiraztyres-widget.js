/**
 * ShirazTyres call-out widget, version 2.0.
 *
 * Drops into the existing marketing site with no build step and no framework:
 *
 *   <div id="shiraztyres-callout"
 *        data-api="https://api.shiraztyres.co.uk/api/v1"
 *        data-site="https://request.shiraztyres.co.uk"
 *        data-phone="+441234567890"></div>
 *   <script src="/shiraztyres-widget.js" defer></script>
 *
 * Renders into a shadow root so the host page's CSS cannot break it, and the
 * widget's CSS cannot leak out.
 *
 * What changed from version 1.0: a call-out is no longer created from here.
 * Specification 4.1 gives every customer an account, and 4.3 requires an explicit
 * tyre-specification decision before a request can be submitted — neither belongs
 * in an anonymous embed. So this widget does the three things it can do honestly
 * and quickly, and then hands over:
 *
 *   1. GET  /public/config          — call-out fee, VAT, opening hours
 *   2. POST /public/coverage        — are we going to come out to them at all?
 *   3. GET  /public/vehicle-lookup  — their car and its tyre size
 *
 * and then sends them to the customer site with the plate and position already
 * filled in, so nothing is typed twice.
 */
(function () {
  'use strict';

  /*
   * Brand tokens, scoped to the shadow root so a host page cannot bleed in.
   * Dark is the ShirazTyres look; `<shiraztyres-widget theme="light">` flips it
   * for hosts with a light layout. No webfont is fetched — this block lives on
   * someone else's page and should not cost them a request.
   */
  var CSS = [
    ':host{all:initial;display:block;' +
      '--st-surface:#0F172A;--st-surface-2:#1E293B;--st-line:#334155;' +
      '--st-ink:#F8FAFC;--st-ink-muted:#CBD5E1;' +
      '--st-brand:#FFD700;--st-brand-strong:#FBBF24;--st-on-brand:#0B1315;' +
      '--st-ok:#4ADE80;--st-bad:#F87171;' +
      'font-family:Sora,Inter,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}',
    ':host([theme="light"]){--st-surface:#FFFFFF;--st-surface-2:#F1F5F9;--st-line:#CBD5E1;' +
      '--st-ink:#0F172A;--st-ink-muted:#475569;' +
      '--st-brand:#C99700;--st-brand-strong:#9A7300;--st-on-brand:#FFFFFF;' +
      '--st-ok:#15803D;--st-bad:#B91C1C}',
    '*,*::before,*::after{box-sizing:border-box}',
    '.card{background:var(--st-surface);border:1px solid var(--st-line);border-radius:16px;padding:24px;max-width:520px;color:var(--st-ink)}',
    'h2{margin:0 0 4px;font-size:20px;font-weight:700;letter-spacing:-.02em}',
    'p.lede{margin:0 0 20px;color:var(--st-ink-muted);font-size:14px;line-height:1.5}',
    'label{display:block;font-size:13px;font-weight:600;margin:0 0 6px}',
    '.field{margin-bottom:14px}',
    'input{width:100%;font:inherit;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:17px;font-weight:700;padding:12px 14px;border:1px solid var(--st-line);border-radius:10px;background:var(--st-surface-2);color:var(--st-ink);text-transform:uppercase;letter-spacing:.18em}',
    'input:focus{outline:2px solid var(--st-brand);outline-offset:1px;border-color:var(--st-brand)}',
    'button{font:inherit;font-weight:700;font-size:15px;border-radius:10px;border:0;padding:14px 18px;cursor:pointer;transition:background .15s,opacity .15s}',
    'button.primary{background:var(--st-brand);color:var(--st-on-brand);width:100%}',
    'button.primary:hover:not(:disabled){background:var(--st-brand-strong)}',
    'button.primary:disabled{opacity:.45;cursor:not-allowed}',
    'button.secondary{background:transparent;border:1px solid var(--st-line);color:var(--st-ink);width:100%}',
    'button.secondary:hover{background:var(--st-surface-2)}',
    '.row{display:flex;gap:10px}.row>*{flex:1}',
    '.note{font-size:13px;color:var(--st-ink-muted);margin:6px 0 0}',
    '.banner{border-radius:10px;padding:12px 14px;font-size:14px;margin-bottom:14px;line-height:1.45}',
    '.banner.info{background:var(--st-surface-2);color:var(--st-ink-muted)}',
    '.banner.bad{background:color-mix(in srgb,var(--st-bad) 14%,transparent);color:var(--st-bad)}',
    '.banner.good{background:color-mix(in srgb,var(--st-ok) 14%,transparent);color:var(--st-ok)}',
    '.vehicle{border:1px solid var(--st-line);border-radius:12px;padding:14px;margin-bottom:14px}',
    '.vehicle strong{display:block;font-size:16px}',
    '.size{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:22px;font-weight:700;margin-top:6px;color:var(--st-brand)}',
    '.spacer{height:10px}',
  ].join('');

  function api(base, path, options) {
    return fetch(base + path, Object.assign({ headers: { 'Content-Type': 'application/json' } }, options))
      .then(function (response) {
        return response.text().then(function (text) {
          var body = text ? JSON.parse(text) : null;
          if (!response.ok) {
            var message = (body && body.detail) || 'Something went wrong. Please try again.';
            throw new Error(message);
          }
          return body;
        });
      });
  }

  function element(tag, attributes, text) {
    var node = document.createElement(tag);
    Object.keys(attributes || {}).forEach(function (key) {
      node.setAttribute(key, attributes[key]);
    });
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function mount(host) {
    var base = (host.getAttribute('data-api') || '/api/v1').replace(/\/$/, '');
    var site = (host.getAttribute('data-site') || '/request').replace(/\/$/, '');
    var phone = host.getAttribute('data-phone') || '';

    var root = host.attachShadow ? host.attachShadow({ mode: 'open' }) : host;
    var style = document.createElement('style');
    style.textContent = CSS;
    root.appendChild(style);

    var card = element('div', { class: 'card' });
    root.appendChild(card);

    var state = { config: null, vehicle: null, position: null, coverage: null, busy: false };

    function go() {
      var url = new URL(site, window.location.origin);
      if (state.vehicle) url.searchParams.set('plate', state.vehicle.plate);
      if (state.position) {
        url.searchParams.set('lat', state.position.latitude.toFixed(6));
        url.searchParams.set('lng', state.position.longitude.toFixed(6));
      }
      host.dispatchEvent(
        new CustomEvent('shiraztyres:handoff', { bubbles: true, detail: { url: url.toString() } })
      );
      window.location.href = url.toString();
    }

    function lookUp(plate) {
      state.busy = true;
      render();
      api(base, '/public/vehicle-lookup/' + encodeURIComponent(plate.replace(/[^A-Za-z0-9]/g, '')))
        .then(function (vehicle) {
          state.vehicle = vehicle;
          state.error = null;
        })
        .catch(function (error) {
          state.vehicle = null;
          state.error = error.message;
        })
        .then(function () {
          state.busy = false;
          render();
        });
    }

    function locate() {
      if (!navigator.geolocation) {
        state.error = 'Your browser cannot share your location. Continue and drop a pin instead.';
        render();
        return;
      }
      state.busy = true;
      render();
      navigator.geolocation.getCurrentPosition(
        function (fix) {
          state.position = { latitude: fix.coords.latitude, longitude: fix.coords.longitude };
          api(base, '/public/coverage', {
            method: 'POST',
            body: JSON.stringify({
              latitude: state.position.latitude.toFixed(6),
              longitude: state.position.longitude.toFixed(6),
            }),
          })
            .then(function (coverage) {
              state.coverage = coverage;
              state.error = null;
            })
            .catch(function (error) {
              state.error = error.message;
            })
            .then(function () {
              state.busy = false;
              render();
            });
        },
        function () {
          state.busy = false;
          state.error = 'We could not read your location. Continue and drop a pin on the map instead.';
          render();
        },
        { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
      );
    }

    function render() {
      card.textContent = '';

      card.appendChild(element('h2', {}, 'Emergency tyre call-out'));
      card.appendChild(
        element('p', { class: 'lede' }, 'Tell us your registration and where you are. We come to you.')
      );

      if (state.config && !state.config.is_open) {
        card.appendChild(element('div', { class: 'banner info' }, state.config.out_of_hours_message));
      }

      if (state.coverage && !state.coverage.covered) {
        card.appendChild(element('div', { class: 'banner bad' }, state.coverage.message));
      } else if (state.coverage && state.coverage.covered) {
        card.appendChild(
          element('div', { class: 'banner good' }, 'Good news — you are inside our service area.')
        );
      }

      var field = element('div', { class: 'field' });
      field.appendChild(element('label', { for: 'plate' }, 'Registration'));
      var input = element('input', { id: 'plate', placeholder: 'AB12 CDE', autocomplete: 'off' });
      if (state.vehicle) input.value = state.vehicle.display_plate;
      field.appendChild(input);
      card.appendChild(field);

      var row = element('div', { class: 'row' });
      var lookUpButton = element('button', { class: 'secondary', type: 'button' }, state.busy ? '…' : 'Look up');
      lookUpButton.disabled = state.busy;
      lookUpButton.addEventListener('click', function () {
        if (input.value.trim()) lookUp(input.value.trim());
      });
      var locateButton = element('button', { class: 'secondary', type: 'button' }, 'Share my location');
      locateButton.disabled = state.busy;
      locateButton.addEventListener('click', locate);
      row.appendChild(lookUpButton);
      row.appendChild(locateButton);
      card.appendChild(row);

      if (state.vehicle) {
        var vehicle = element('div', { class: 'vehicle' });
        vehicle.appendChild(element('strong', {}, state.vehicle.description || state.vehicle.display_plate));
        vehicle.appendChild(
          element('div', { class: 'size' }, state.vehicle.tyre_size_front || 'tyre size not on record')
        );
        vehicle.appendChild(
          element(
            'p',
            { class: 'note' },
            'You will be asked to confirm this size before your request is sent.'
          )
        );
        card.appendChild(element('div', { class: 'spacer' }));
        card.appendChild(vehicle);
      }

      if (state.error) {
        card.appendChild(element('div', { class: 'banner bad' }, state.error));
      }

      card.appendChild(element('div', { class: 'spacer' }));
      var next = element('button', { class: 'primary', type: 'button' }, 'Continue');
      next.disabled = state.busy || (state.coverage !== null && !state.coverage.covered);
      next.addEventListener('click', function () {
        if (!state.vehicle && input.value.trim()) {
          state.vehicle = { plate: input.value.trim().replace(/[^A-Za-z0-9]/g, '') };
        }
        go();
      });
      card.appendChild(next);

      if (state.config && state.config.callout_fee_enabled) {
        card.appendChild(
          element(
            'p',
            { class: 'note' },
            'Call-out fee £' +
              state.config.callout_fee +
              ', plus parts and labour and VAT at ' +
              state.config.vat_rate +
              '%. You pay once the work is finished.'
          )
        );
      }

      if (phone) {
        card.appendChild(element('p', { class: 'note' }, 'Prefer to talk? Call us on ' + phone + '.'));
      }
    }

    render();

    api(base, '/public/config')
      .then(function (config) {
        state.config = config;
        render();
      })
      .catch(function () {
        // The widget is useful without the fee and the opening hours; do not
        // block it on a config call that failed.
      });
  }

  function boot() {
    var hosts = [];
    var main = document.getElementById('shiraztyres-callout');
    if (main) hosts.push(main);
    Array.prototype.forEach.call(document.querySelectorAll('[data-shiraztyres-callout]'), function (node) {
      if (hosts.indexOf(node) === -1) hosts.push(node);
    });
    hosts.forEach(mount);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
