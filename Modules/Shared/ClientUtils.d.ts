/**
 * Type declarations for `ClientUtils.luau` — small client-side text helpers.
 *
 * Every member is defined with a dot and takes no `self`, so they are all
 * declared as properties and compile to `ClientUtils.foo(...)`.
 */

declare namespace ClientUtils {
	/** Any instance with `Text` and `MaxVisibleGraphemes`. */
	type TextObject = TextLabel | TextButton | TextBox;
}

interface ClientUtilsModule {
	/**
	 * Wraps `text` in a rich-text `<font color>` tag using `color`. The text is
	 * XML-escaped first, so user input cannot inject markup.
	 */
	resolveRichColor: (text: string, color: Color3) => string;

	/**
	 * Reveals `label`'s text one grapheme at a time and returns a function that
	 * finishes the animation immediately.
	 *
	 * Passing `text` overwrites the label's text first; otherwise the current
	 * text is used. `secondsPerGrapheme` defaults to `0.04`. Starting a new
	 * type-out on a label that is already animating finishes the previous one.
	 */
	typeOut: (
		label: ClientUtils.TextObject,
		text?: string,
		secondsPerGrapheme?: number,
	) => () => void;

	/**
	 * Recursively walks `tbl`, calling `callback(key, value)` for every leaf.
	 * Nested tables are only passed to the callback when `callbackOnTables` is
	 * `true`; either way they are still descended into.
	 */
	deepPairs: (
		tbl: object,
		callback: (key: unknown, value: unknown) => void,
		callbackOnTables?: boolean,
	) => void;
}

declare const ClientUtils: ClientUtilsModule;

export = ClientUtils;
