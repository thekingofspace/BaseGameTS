/**
 * Type declarations for `VideLoader.luau`.
 *
 * The module returns a single function, so there is no table to type: it takes
 * a declarative spec table and builds the instance tree through vide's
 * `create`. Nothing from vide itself is typed here — values that are vide
 * internals (state sources, derived values, event handlers) are `unknown`.
 *
 * Because the module returns the function directly, the export is
 * `declare function VideLoader(...)`, not a const holding a table.
 */

declare namespace VideLoader {
	/**
	 * One node of the tree.
	 *
	 * Every string key that is not `ClassName`, `Children`, `Attributes` or
	 * `Tags` is forwarded straight to vide as a property — that includes plain
	 * values, vide sources, and event handler functions.
	 */
	interface Spec {
		/** Class to create, or an existing `Instance` to configure. Required. */
		ClassName: string | Instance;
		/**
		 * Child nodes. Any entry that is a table with a `ClassName` is treated
		 * as a nested `Spec` and built recursively; anything else is handed to
		 * vide untouched (a component result, a source, a cleanup function...),
		 * which is why this is not narrowed to `Array<Spec>`.
		 */
		Children?: Array<unknown>;
		/** Applied with `Instance:SetAttribute` after the instance is created. */
		Attributes?: Record<string, unknown>;
		/** Applied with `Instance:AddTag` after the instance is created. */
		Tags?: Array<string>;
		/** Properties, vide sources and event handlers. */
		[property: string]: unknown;
	}
}

/**
 * Builds an `Instance` from a spec table. Throws if `spec` is not a table or
 * has no `ClassName`.
 */
declare function VideLoader(spec: VideLoader.Spec): Instance;

export = VideLoader;
