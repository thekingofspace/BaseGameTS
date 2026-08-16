/**
 * Type declarations for `Flags.luau`.
 *
 * Every leaf is rewritten at require time to the dotted path that reaches it,
 * so `Flags.NetworkResponse.OK` holds the string `"Flags.NetworkResponse.OK"`.
 * Both the outer table and each category are `table.freeze`d.
 *
 * Note the spelling of `Recieved` — it is the runtime key, not a typo to fix.
 */

declare namespace Flags {
	/** Status codes handed back by networking round trips. */
	interface NetworkResponse {
		/** `"Flags.NetworkResponse.OK"` */
		readonly OK: string;
		/** `"Flags.NetworkResponse.Recieved"` — spelling is intentional. */
		readonly Recieved: string;
		/** `"Flags.NetworkResponse.Bad"` */
		readonly Bad: string;
		/** `"Flags.NetworkResponse.Debounced"` */
		readonly Debounced: string;
	}
}

interface FlagsModule {
	readonly NetworkResponse: Flags.NetworkResponse;
}

declare const Flags: FlagsModule;

export = Flags;
