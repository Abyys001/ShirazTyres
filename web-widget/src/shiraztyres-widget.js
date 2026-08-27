/**
 * ShirazTyres emergency call-out widget.
 *
 * Drops into the existing website with no build step and no framework:
 *
 *   <div id="shiraztyres-callout"
 *        data-api="https://api.shiraztyres.co.uk/api/v1"
 *        data-phone="+441234567890"></div>
 *   <script src="/shiraztyres-widget.js" defer></script>
 *
 * Renders into a shadow root so the host page's CSS cannot break it, and the
 * widget's CSS cannot leak out. Talks only to the public endpoints:
 * GET /vehicle-lookup/{plate}, POST /auth/otp/request, POST /public/bookings.
 */
(function () {
  'use strict';

  var ISSUES = [
    ['puncture', 'Puncture'],
    ['blowout', 'Blowout'],
    ['tyre_damage', 'Tyre damage'],
    ['wheel_change', 'Wheel change'],
    ['other', 'Something else'],
  ];

  var CSS = [
    ':host{all:initial;display:block;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}',
    '*,*::before,*::after{box-sizing:border-box}',
    '.card{background:#fff;border:1px solid #e4e4e7;border-radius:16px;padding:24px;max-width:520px;color:#18181b}',
    'h2{margin:0 0 4px;font-size:20px}',
    'p.lede{margin:0 0 20px;color:#52525b;font-size:14px;line-height:1.5}',
    'label{display:block;font-size:13px;font-weight:600;margin:0 0 6px}',
    '.field{margin-bottom:14px}',
    'input,select,textarea{width:100%;font:inherit;font-size:15px;padding:12px 14px;border:1px solid #d4d4d8;border-radius:10px;background:#fff;color:inherit}',
    'input:focus,select:focus,textarea:focus{outline:2px solid #d32f2f;outline-offset:1px;border-color:#d32f2f}',
    'textarea{min-height:76px;resize:vertical}',
    'button{font:inherit;font-weight:600;font-size:15px;border-radius:10px;border:0;padding:14px 18px;cursor:pointer}',
    'button.primary{background:#d32f2f;color:#fff;width:100%}',
    'button.primary:disabled{background:#e5a3a3;cursor:not-allowed}',
    'button.link{background:none;color:#d32f2f;padding:8px 0;text-decoration:underline}',
    '.row{display:flex;gap:10px}.row>*{flex:1}',
    '.chip-row{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px}',
    '.chip{border:1px solid #d4d4d8;background:#fff;color:#3f3f46;padding:8px 14px;border-radius:999px;font-size:14px}',
    '.chip[aria-pressed="true"]{background:#d32f2f;border-color:#d32f2f;color:#fff}',
    '.note{font-size:13px;color:#52525b;margin:6px 0 0}',
    '.error{font-size:13px;color:#b91c1c;margin:6px 0 0}',
    '.banner{border-radius:10px;padding:12px 14px;font-size:14px;margin-bottom:14px}',
    '.banner.info{background:#f4f4f5;color:#3f3f46}',
    '.banner.bad{background:#fef2f2;color:#b91c1c}',
    '.banner.good{background:#f0fdf4;color:#166534}',
    '.done{text-align:center;padding:12px 0}',
    '.ref{font-size:26px;font-weight:700;letter-spacing:1px;margin:10px 0}',
    '.code{letter-spacing:8px;text-align:center;font-size:22px}',
    '.hidden{display:none}',
  ].join('\n');

  /** @param {string} tag @param {Object<string,string>=} attrs @param {string=} text */
  function el(tag, attrs, text) {
    var node = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (key) { node.setAttribute(key, attrs[key]); });
    }
    if (text !== undefined) { node.textContent = text; }
    return node;
  }

  function Widget(host) {
    this.host = host;
    this.api = (host.getAttribute('data-api') || '/api/v1').replace(/\/$/, '');
    this.phone = host.getAttribute('data-phone') || '';
    this.state = {
      step: 'details',
      issue: 'puncture',
      vehicle: null,
      latitude: null,
      longitude: null,
      resendAfter: 0,
      reference: '',
    };
    this.root = host.attachShadow({ mode: 'open' });
    this.root.appendChild(el('style', undefined, CSS));
    this.card = el('div', { class: 'card' });
    this.root.appendChild(this.card);
    this.renderDetails();
  }

  /** Every error the API returns has the same shape: {detail, errors:{field:[msg]}}. */
  Widget.prototype.request = function (path, options) {
    var url = this.api + path;
    return fetch(url, Object.assign({ headers: { 'Content-Type': 'application/json' } }, options))
      .then(function (response) {
        return response.text().then(function (body) {
          var data = null;
          try { data = body ? JSON.parse(body) : null; } catch (e) { data = null; }
          if (response.ok) { return data; }
          var detail = (data && data.detail) || 'Something went wrong. Please try again.';
          var errors = (data && data.errors) || {};
          var first = Object.keys(errors)[0];
          if (first && Array.isArray(errors[first]) && errors[first].length) {
            detail = errors[first][0];
          }
          var error = new Error(detail);
          error.fields = errors;
          error.status = response.status;
          throw error;
        });
      });
  };

  Widget.prototype.banner = function (kind, message) {
    var node = el('div', { class: 'banner ' + kind }, message);
    this.card.insertBefore(node, this.card.firstChild);
    return node;
  };

  Widget.prototype.field = function (labelText, control, hint) {
    var wrap = el('div', { class: 'field' });
    var id = 'f' + Math.random().toString(36).slice(2, 8);
    control.id = id;
    wrap.appendChild(el('label', { for: id }, labelText));
    wrap.appendChild(control);
    if (hint) { wrap.appendChild(el('p', { class: 'note' }, hint)); }
    this.card.appendChild(wrap);
    return control;
  };

  Widget.prototype.renderDetails = function () {
    var self = this;
    this.card.textContent = '';
    this.card.appendChild(el('h2', undefined, 'Emergency tyre call-out'));
    this.card.appendChild(el('p', { class: 'lede' },
      'Tell us where you are and what has happened. We will text you a code to confirm your number, then a fitter comes to you.'));

    var chips = el('div', { class: 'chip-row' });
    ISSUES.forEach(function (pair) {
      var chip = el('button', {
        type: 'button',
        class: 'chip',
        'aria-pressed': String(pair[0] === self.state.issue),
        'data-issue': pair[0],
      }, pair[1]);
      chip.addEventListener('click', function () {
        self.state.issue = pair[0];
        Array.prototype.forEach.call(chips.children, function (other) {
          other.setAttribute('aria-pressed', String(other.getAttribute('data-issue') === pair[0]));
        });
      });
      chips.appendChild(chip);
    });
    this.card.appendChild(el('label', undefined, 'What has happened?'));
    this.card.appendChild(chips);

    var plateRow = el('div', { class: 'field' });
    var plateId = 'f' + Math.random().toString(36).slice(2, 8);
    plateRow.appendChild(el('label', { for: plateId }, 'Number plate'));
    var plateInner = el('div', { class: 'row' });
    var plate = el('input', { type: 'text', id: plateId, name: 'plate', placeholder: 'AB12 CDE', autocomplete: 'off' });
    var lookupBtn = el('button', { type: 'button', class: 'chip' }, 'Look up');
    plateInner.appendChild(plate);
    lookupBtn.style.flex = '0 0 auto';
    plateInner.appendChild(lookupBtn);
    plateRow.appendChild(plateInner);
    var plateNote = el('p', { class: 'note' }, 'Optional, but it tells us which tyre to load.');
    plateRow.appendChild(plateNote);
    this.card.appendChild(plateRow);

    lookupBtn.addEventListener('click', function () {
      var value = plate.value.trim();
      if (!value) { return; }
      lookupBtn.disabled = true;
      plateNote.className = 'note';
      plateNote.textContent = 'Looking up…';
      self.request('/vehicle-lookup/' + encodeURIComponent(value), { method: 'GET' })
        .then(function (vehicle) {
          self.state.vehicle = vehicle;
          plateNote.className = 'note';
          plateNote.textContent = [vehicle.description, vehicle.tyre_size_front]
            .filter(Boolean).join(' · ') || 'Vehicle found.';
          if (vehicle.tyre_size_front && !tyre.value) { tyre.value = vehicle.tyre_size_front; }
        })
        .catch(function (error) {
          self.state.vehicle = null;
          plateNote.className = 'error';
          plateNote.textContent = error.message;
        })
        .then(function () { lookupBtn.disabled = false; });
    });

    var tyre = this.field('Tyre size (if you know it)',
      el('input', { type: 'text', placeholder: '205/55 R16' }));

    var location = this.field('Where are you?',
      el('textarea', { placeholder: 'M6 northbound, just past junction 4' }),
      'An address, a junction number or a landmark is enough.');

    var geoNote = el('p', { class: 'note' }, '');
    var geoBtn = el('button', { type: 'button', class: 'link' }, 'Use my current location');
    geoBtn.addEventListener('click', function () {
      if (!navigator.geolocation) {
        geoNote.className = 'error';
        geoNote.textContent = 'This browser cannot share your location.';
        return;
      }
      geoNote.className = 'note';
      geoNote.textContent = 'Getting your location…';
      navigator.geolocation.getCurrentPosition(function (position) {
        self.state.latitude = position.coords.latitude;
        self.state.longitude = position.coords.longitude;
        geoNote.className = 'note';
        geoNote.textContent = 'Location shared with ShirazTyres.';
      }, function () {
        geoNote.className = 'error';
        geoNote.textContent = 'Could not get your location — please type it above.';
      }, { enableHighAccuracy: true, timeout: 12000 });
    });
    this.card.appendChild(geoBtn);
    this.card.appendChild(geoNote);

    var name = this.field('Your name', el('input', { type: 'text', autocomplete: 'name' }));
    var contact = this.field('Mobile number',
      el('input', { type: 'tel', autocomplete: 'tel', placeholder: '07700 900123' }),
      'We text a code to this number to stop hoax call-outs.');
    var description = this.field('Anything else we should know?',
      el('textarea', { placeholder: 'Front nearside, spare is flat, two children in the car.' }));

    var error = el('p', { class: 'error hidden' });
    this.card.appendChild(error);

    var submit = el('button', { type: 'button', class: 'primary' }, 'Send code and continue');
    this.card.appendChild(submit);
    if (this.phone) {
      this.card.appendChild(el('p', { class: 'note' }, 'Prefer to talk? Call ' + this.phone + '.'));
    }

    submit.addEventListener('click', function () {
      error.className = 'error hidden';
      if (!contact.value.replace(/\D/g, '').match(/\d{10,}/)) {
        error.className = 'error';
        error.textContent = 'Enter a full UK mobile number.';
        return;
      }
      if (!location.value.trim() && self.state.latitude === null) {
        error.className = 'error';
        error.textContent = 'Tell us where you are, or share your location.';
        return;
      }
      self.state.payload = {
        issue_type: self.state.issue,
        plate: plate.value.trim(),
        tyre_size: tyre.value.trim(),
        contact_name: name.value.trim(),
        contact_phone: contact.value.trim(),
        description: description.value.trim(),
        location_text: location.value.trim(),
        latitude: self.state.latitude,
        longitude: self.state.longitude,
      };
      submit.disabled = true;
      submit.textContent = 'Sending code…';
      self.request('/auth/otp/request', {
        method: 'POST',
        body: JSON.stringify({ phone: contact.value.trim(), purpose: 'booking' }),
      })
        .then(function (challenge) { self.renderVerify(challenge); })
        .catch(function (err) {
          error.className = 'error';
          error.textContent = err.message;
          submit.disabled = false;
          submit.textContent = 'Send code and continue';
        });
    });
  };

  Widget.prototype.renderVerify = function (challenge) {
    var self = this;
    this.card.textContent = '';
    this.card.appendChild(el('h2', undefined, 'Confirm your number'));
    this.card.appendChild(el('p', { class: 'lede' },
      'We texted a code to ' + this.state.payload.contact_phone + '. Enter it to send your call-out.'));

    var code = this.field('Code', el('input', { type: 'text', inputmode: 'numeric', class: 'code', maxlength: '8' }));
    if (challenge && challenge.debug_code) { code.value = challenge.debug_code; }

    var error = el('p', { class: 'error hidden' });
    this.card.appendChild(error);

    var submit = el('button', { type: 'button', class: 'primary' }, 'Send my call-out');
    this.card.appendChild(submit);

    var back = el('button', { type: 'button', class: 'link' }, 'Change my details');
    back.addEventListener('click', function () { self.renderDetails(); });
    this.card.appendChild(back);

    submit.addEventListener('click', function () {
      error.className = 'error hidden';
      submit.disabled = true;
      submit.textContent = 'Sending…';
      var body = Object.assign({}, self.state.payload, { code: code.value.trim() });
      self.request('/public/bookings', { method: 'POST', body: JSON.stringify(body) })
        .then(function (booking) { self.renderDone(booking); })
        .catch(function (err) {
          error.className = 'error';
          error.textContent = err.message;
          submit.disabled = false;
          submit.textContent = 'Send my call-out';
        });
    });
  };

  Widget.prototype.renderDone = function (booking) {
    this.card.textContent = '';
    var done = el('div', { class: 'done' });
    done.appendChild(el('h2', undefined, 'We are on it'));
    done.appendChild(el('div', { class: 'ref' }, booking.reference));
    done.appendChild(el('p', { class: 'lede' },
      'Your call-out is with the shop now. Keep this reference handy'
      + (this.phone ? ' — if anything changes, call ' + this.phone + '.' : '.')));
    this.card.appendChild(done);
    this.host.dispatchEvent(new CustomEvent('shiraztyres:booked', {
      detail: booking,
      bubbles: true,
    }));
  };

  function boot() {
    var hosts = document.querySelectorAll('[id="shiraztyres-callout"],[data-shiraztyres-callout]');
    Array.prototype.forEach.call(hosts, function (host) {
      if (!host.shadowRoot) { new Widget(host); }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
