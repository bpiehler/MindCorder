class Dictation extends Native("xs_dictation_destructor") {
	constructor(options) {
		super();
		native("xs_dictation_create").call(this, options);
	}
	start() {
		return native("xs_dictation_start").call(this);
	}
	stop() {
		return native("xs_dictation_stop").call(this);
	}
	read() {
		return native("xs_dictation_read").call(this);
	}
	close() {
		return native("xs_dictation_close").call(this);
	}
}

export { Dictation };
