# Changelog

## [1.0.0](https://github.com/srepollock/touchbar-buddy/compare/v0.1.0...v1.0.0) (2026-11-20)


### Features

* **app:** add animated dashboard with auto-popup and optional TTS ([3cd4c3d](https://github.com/srepollock/touchbar-buddy/commit/3cd4c3d87d0dbf567a33096306ae69d72edd1a86))
* **app:** add session watcher, Control Strip status icon and menu ([12fbf7b](https://github.com/srepollock/touchbar-buddy/commit/12fbf7b1566d1214db0ffe166be6ce5d96238d98))
* **app:** chatty mode with wandering avatar and random updates ([1480a81](https://github.com/srepollock/touchbar-buddy/commit/1480a8172dbaf5239d6c0444a3b936ed4b230fbc))
* **app:** install hooks as a local Claude Code plugin ([b63c434](https://github.com/srepollock/touchbar-buddy/commit/b63c434b0ae13abc2272f7729cc3560850200a3a))
* **app:** jump to the tapped session's iTerm tab ([9e6ffd7](https://github.com/srepollock/touchbar-buddy/commit/9e6ffd769b8ea70e33cf1ebf1d9f726b83b2134e))
* **app:** reply to permission prompts and questions from the Touch Bar ([0824681](https://github.com/srepollock/touchbar-buddy/commit/0824681112074e5e3fa8377e1232c494a4983459))
* **app:** swipeable speech bubble and close-box teardown ([365e028](https://github.com/srepollock/touchbar-buddy/commit/365e028cc1bb9e17d2f0d83f77fe385583fbb266))
* **characters:** add four original animated built-in characters ([6ed04d4](https://github.com/srepollock/touchbar-buddy/commit/6ed04d47a6f9495b66a7daf89818e1a0bcb0d7e6))
* **characters:** add six more original animated characters ([072e912](https://github.com/srepollock/touchbar-buddy/commit/072e912e529734d638f4eaebf3099859424f3bbc))
* **core:** add character loading and animation decoding ([8f241ce](https://github.com/srepollock/touchbar-buddy/commit/8f241ce916b93dd2fe46548d74b7ba7211f36e9f))
* **core:** add per-character speech templates ([764b23f](https://github.com/srepollock/touchbar-buddy/commit/764b23f540a146897271fc68aeb6aa3f761747ab))
* **core:** add session model and hook event reducer ([7cf62d1](https://github.com/srepollock/touchbar-buddy/commit/7cf62d1ba2c2ca34b937f810898916841efbe8a9))
* **core:** add session ordering, decay, popup and pruning logic ([19ee23b](https://github.com/srepollock/touchbar-buddy/commit/19ee23b6937243e0ada94243ae09ad6bfd01be8f))
* **core:** add settings.local.json hook installer ([9411714](https://github.com/srepollock/touchbar-buddy/commit/94117144ad957c4dd412cb26cb4d0ac4cffa31f4))
* **hook:** add session store and touchbuddy-hook CLI ([60f3032](https://github.com/srepollock/touchbar-buddy/commit/60f30320f6d95ad26ffb9ead9c0e033b42281105))
* **spike:** scaffold package and prove private Touch Bar APIs ([913b7f0](https://github.com/srepollock/touchbar-buddy/commit/913b7f0da3818bc843f63fd9d5c0df021ee2fb09))
* TouchBuddy v1 — Claude Code session status on the Touch Bar ([df9bc2c](https://github.com/srepollock/touchbar-buddy/commit/df9bc2c993724062b51d68465480eee5ef4f87e3))


### Bug Fixes

* **app:** bound iTerm focus AppleScript and use safe fallbacks ([533b4f3](https://github.com/srepollock/touchbar-buddy/commit/533b4f35f10d09149a4edc49c37a875748f2fcac))
* **app:** fail closed on overlapping prompts and lock session updates ([81dd61e](https://github.com/srepollock/touchbar-buddy/commit/81dd61e5c594e2ed3ce732eb777e28fa900f0f01))
* **app:** find iTerm sessions in hotkey windows and widen safe quick replies ([426188c](https://github.com/srepollock/touchbar-buddy/commit/426188c8bff3d07e54240574d32ebeded5426b4f))
* **app:** keep chatter on the prompted session while replies show ([cc5dcbd](https://github.com/srepollock/touchbar-buddy/commit/cc5dcbd50718c405020848b0ed1e6858b8a5eebf))
* **app:** keep menu without characters, propagate decay, use spec colours ([164d71b](https://github.com/srepollock/touchbar-buddy/commit/164d71bedf36fb43ad44eaa4f2ad04caef36d6ee))
* **app:** make Touch Bar taps work and pin manual dashboard ([24e71a2](https://github.com/srepollock/touchbar-buddy/commit/24e71a2efaf5e4ca914483868935f73b7bd0c746))
* **app:** match prompt footer exactly and pin prompt identity ([c9b7e5a](https://github.com/srepollock/touchbar-buddy/commit/c9b7e5a107c3ead633fcd2627d3baa9f9ef69643))
* **app:** surface AppleScript errors and never reopen iTerm ([201a628](https://github.com/srepollock/touchbar-buddy/commit/201a6285a3d75538e923ac21e69f5b4bec361bab))
* **app:** verify on-screen prompt and per-prompt identity before quick replies ([cb5364c](https://github.com/srepollock/touchbar-buddy/commit/cb5364c6fdc2be998a05d1dd6e51d05ecbafacb9))
* **characters:** sharpen Tape and Orbit alerts ([f1d2260](https://github.com/srepollock/touchbar-buddy/commit/f1d226029a7677bd6dbff89226e4bf17dcdd6355))
* **core:** dedupe same-prompt popups and decay finished speech lines ([f9bea19](https://github.com/srepollock/touchbar-buddy/commit/f9bea19b670234e78a9284e5a33efe142a7cb3c4))
* **core:** drop prompt identity when several tool calls are in flight ([7d8ceb3](https://github.com/srepollock/touchbar-buddy/commit/7d8ceb3f2751dcdf9da9552deb78112337d1714c))
* **core:** harden character discovery and frame decoding ([f6ce17f](https://github.com/srepollock/touchbar-buddy/commit/f6ce17f3bb96701a98bbde6ebb288c7204468106))
* **core:** keep needs-input visible during parallel tool activity ([de3929b](https://github.com/srepollock/touchbar-buddy/commit/de3929bb4916ade8745640540150da38f6c1a73b))
* **core:** make hook installer backups and writes non-destructive ([9f931d7](https://github.com/srepollock/touchbar-buddy/commit/9f931d7d44ebb9346120afaabbdea0dad41a4105))
* **core:** render speech templates in a single pass ([4371a90](https://github.com/srepollock/touchbar-buddy/commit/4371a903fd27e4df61dc8c7b74a22d4ee2223a9d))
* **core:** version the plugin by hooks.json content hash ([13811ad](https://github.com/srepollock/touchbar-buddy/commit/13811ad5c02e2e8963f6686fdab4050859586120))
* **hook:** harden stdin read, process lookup and file permissions ([b2596c4](https://github.com/srepollock/touchbar-buddy/commit/b2596c4856f662eae5d22f4c8df4572c2e9e15e8))
* **release:** clean install and retryable signing setup ([1b67524](https://github.com/srepollock/touchbar-buddy/commit/1b675240133593e784f92d094b98e38844271d26))


### Miscellaneous Chores

* **release:** release TouchBuddy as 1.0.0 ([1530a8f](https://github.com/srepollock/touchbar-buddy/commit/1530a8f75630b4350af4404ce5ceee3204cc87e9))
