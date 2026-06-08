function app() {
  return {
    classes: [],
    allSpells: [],
    classSlug: 'mago',
    levelInput: 5,
    session: {
      level: null,
      max_slots: [0, 0, 0, 0, 0, 0, 0, 0, 0],
      slots_remaining: [0, 0, 0, 0, 0, 0, 0, 0, 0],
      at_hand: [],
    },
    tab: 'all',
    search: '',
    levelFilter: '',
    expanded: {},
    toast: '',
    toastKind: '',
    toastTimer: null,
    undoPending: false,
    undoTimer: null,
    theme: 'light',
    loading: false,
    pulsedSlot: null,

    foldDiacritics(s) {
      return s.normalize('NFD').replace(/[̀-ͯ]/g, '');
    },

    async init() {
      this.theme =
        document.documentElement.getAttribute('data-theme') || 'light';
      await Promise.all([this.loadClasses(), this.loadAllSpells()]);
      const sharedSpell = new URLSearchParams(window.location.search).get('spell');
      const savedClass = this.storageGet('cantrip.activeClass');
      const hasSavedClass = savedClass && this.classes.find((c) => c.slug === savedClass);
      if (hasSavedClass) {
        this.classSlug = savedClass;
      } else if (sharedSpell) {
        this.classSlug = 'todas';
      } else if (
        this.classes.length &&
        !this.classes.find((c) => c.slug === this.classSlug)
      ) {
        this.classSlug = this.classes[0].slug;
      }
      await this.onClassChange();
      if (sharedSpell) {
        const found = this.allSpells.find((s) => s.slug === sharedSpell);
        if (found) this.search = found.name;
        this.expanded = { ...this.expanded, [sharedSpell]: true };
        setTimeout(() => {
          const el = document.querySelector(`[data-spell="${sharedSpell}"]`);
          if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }, 150);
      }
    },

    async onClassChange() {
      this.loading = true;
      try {
        this.expanded = {};
        this.storageSet('cantrip.activeClass', this.classSlug);
        if (this.classSlug === 'todas') {
          this.session = { level: null, max_slots: [], slots_remaining: [], at_hand: [] };
        } else {
          await this.initSession();
          if (this.session.level !== null) {
            this.levelInput = this.session.level;
          } else {
            const savedLevel = this.storageGet(
              `cantrip.levelInput.${this.classSlug}`,
            );
            if (savedLevel !== null)
              this.levelInput = parseInt(savedLevel, 10) || 1;
            if (!this.levelInput || this.levelInput < 1) this.levelInput = 1;
            await this.setLevel();
          }
        }
      } finally {
        this.loading = false;
      }
    },

    async loadClasses() {
      const r = await fetch('/classes');
      this.classes = await r.json();
    },
    async loadAllSpells() {
      const r = await fetch('/classes/todas/spells');
      this.allSpells = r.ok ? await r.json() : [];
    },
    async initSession() {
      const saved = this.loadLocal();
      const r = await fetch(`/classes/${this.classSlug}/session/init`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          level: saved?.level ?? null,
          slots_remaining: saved?.slots_remaining ?? null,
          at_hand: saved?.at_hand ?? null,
        }),
      });
      if (r.ok) {
        this.session = await r.json();
        this.saveLocal();
      }
    },

    async setLevel() {
      this.loading = true;
      try {
        const r = await fetch(`/classes/${this.classSlug}/session`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ level: this.levelInput }),
        });
        if (!r.ok) {
          this.flash((await r.json()).error || 'Could not set level');
          return;
        }
        this.session = await r.json();
        this.saveLocal();
      } finally {
        this.loading = false;
      }
    },

    async cast(spellLevel) {
      const prev = this.session;
      const newRemaining = [...this.session.slots_remaining];
      newRemaining[spellLevel - 1] = Math.max(0, newRemaining[spellLevel - 1] - 1);
      this.session = { ...this.session, slots_remaining: newRemaining };
      this.pulsedSlot = spellLevel;
      setTimeout(() => { this.pulsedSlot = null; }, 600);
      if (newRemaining[spellLevel - 1] === 0) {
        this.flash(`Slots de nível ${spellLevel} esgotados!`, 'warning');
      }

      const r = await fetch(`/classes/${this.classSlug}/cast`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ spell_level: spellLevel }),
      });
      if (!r.ok) {
        this.session = prev;
        this.saveLocal();
        const err = await r.json().catch(() => ({}));
        this.flash(err.error || 'Falha ao conjurar');
        return;
      }
      this.session = await r.json();
      this.saveLocal();
    },

    async longRest() {
      const prev = this.session;
      this.session = { ...this.session, slots_remaining: [...this.session.max_slots] };
      this.pulsedSlot = 'all';
      setTimeout(() => { this.pulsedSlot = null; }, 600);
      this.saveLocal();

      const r = await fetch(`/classes/${this.classSlug}/long-rest`, { method: 'POST' });
      if (!r.ok) {
        this.session = prev;
        this.saveLocal();
        const err = await r.json().catch(() => ({}));
        this.flash(err.error || 'Falha no descanso longo');
        return;
      }
      this.session = await r.json();
      this.saveLocal();
    },

    async shortRest() {
      const prev = this.session;
      this.session = { ...this.session, slots_remaining: [...this.session.max_slots] };
      this.pulsedSlot = 'all';
      setTimeout(() => { this.pulsedSlot = null; }, 600);
      this.saveLocal();

      const r = await fetch(`/classes/${this.classSlug}/short-rest`, { method: 'POST' });
      if (!r.ok) {
        this.session = prev;
        this.saveLocal();
        const err = await r.json().catch(() => ({}));
        this.flash(err.error || 'Falha no descanso curto');
        return;
      }
      this.session = await r.json();
      this.saveLocal();
    },

    async toggleAtHand(spell) {
      if (this.isAtHand(spell)) {
        const r = await fetch(
          `/classes/${this.classSlug}/at-hand/${spell.slug}`,
          { method: 'DELETE' },
        );
        if (r.ok) {
          this.session = await r.json();
          this.saveLocal();
        }
      } else {
        const r = await fetch(`/classes/${this.classSlug}/at-hand`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ spell_slug: spell.slug }),
        });
        if (r.ok) {
          this.session = await r.json();
          this.saveLocal();
        }
      }
    },
    async clearAtHand() {
      const r = await fetch(`/classes/${this.classSlug}/at-hand/clear`, {
        method: 'POST',
      });
      if (r.ok) {
        this.session = await r.json();
        this.saveLocal();
      }
    },

    isAtHand(spell) {
      return this.session.at_hand.includes(spell.slug);
    },
    canCast(level) {
      if (level < 1 || level > 9) return false;
      return this.session.slots_remaining[level - 1] > 0;
    },
    toggleExpand(spell) {
      this.expanded = {
        ...this.expanded,
        [spell.slug]: !this.expanded[spell.slug],
      };
    },

    toggleTheme() {
      this.theme = this.theme === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', this.theme);
      this.storageSet('cantrip.theme', this.theme);
    },

    async shareSpell(spell) {
      const url = `${window.location.origin}${window.location.pathname}?spell=${spell.slug}`;
      try {
        await navigator.clipboard.writeText(url);
        this.flash('Link copiado!', 'success');
      } catch {
        this.flash('Não foi possível copiar o link');
      }
    },

    startWithUndo(message, callback) {
      clearTimeout(this.undoTimer);
      this.undoPending = true;
      this.toast = message;
      this.toastKind = 'warning';
      clearTimeout(this.toastTimer);
      this.undoTimer = setTimeout(() => {
        this.undoPending = false;
        this.toast = '';
        callback();
      }, 2500);
    },

    cancelUndo() {
      clearTimeout(this.undoTimer);
      this.undoPending = false;
      this.toast = '';
    },

    flash(msg, kind = 'error') {
      this.toast = msg;
      this.toastKind = kind;
      clearTimeout(this.toastTimer);
      this.toastTimer = setTimeout(() => {
        this.toast = '';
      }, 3000);
    },

    get classSpells() {
      if (this.classSlug === 'todas') return this.allSpells;
      return this.allSpells.filter((s) =>
        s.classes.some(
          (c) => this.foldDiacritics(c.toLowerCase()) === this.classSlug,
        ),
      );
    },

    /** Slot columns to show — only spell levels where max > 0. */
    get activeSlots() {
      return this.session.max_slots
        .map((max, i) => ({
          spellLevel: i + 1,
          max,
          remaining: this.session.slots_remaining[i],
        }))
        .filter((col) => col.max > 0);
    },

    get filteredSpells() {
      let pool;
      if (this.tab === 'at-hand') {
        pool = this.allSpells.filter((s) =>
          this.session.at_hand.includes(s.slug),
        );
      } else if (this.search.trim()) {
        pool = this.allSpells;
      } else {
        pool = this.classSpells;
      }

      const q = this.foldDiacritics(this.search.trim().toLowerCase());
      const lvl =
        this.levelFilter === '' ? null : parseInt(this.levelFilter, 10);

      return pool.filter((s) => {
        if (lvl !== null && s.level !== lvl) return false;
        if (q && !this.foldDiacritics(s.name.toLowerCase()).includes(q))
          return false;
        return true;
      });
    },

    // Mirror session into localStorage and replay on load — server actor is in-memory only.
    storageKey() {
      return `cantrip.session.${this.classSlug}`;
    },
    storageGet(key) {
      try {
        return localStorage.getItem(key);
      } catch {
        return null;
      }
    },
    storageSet(key, value) {
      try {
        localStorage.setItem(key, value);
      } catch {}
    },
    saveLocal() {
      if (!this.classSlug) return;
      this.storageSet(this.storageKey(), JSON.stringify(this.session));
      this.storageSet(`cantrip.levelInput.${this.classSlug}`, this.levelInput);
    },
    loadLocal() {
      const raw = this.storageGet(this.storageKey());
      if (!raw) return null;
      try {
        return JSON.parse(raw);
      } catch {
        return null;
      }
    },

  };
}
