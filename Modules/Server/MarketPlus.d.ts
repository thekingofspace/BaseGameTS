/**
 * Type declarations for `MarketPlus.luau` — gamepass / developer product
 * purchase handling with optional analytics.
 *
 * The Luau types product IDs as `any`; they are narrowed to `number | string`
 * here since that is what the MarketplaceService calls actually accept.
 */

declare namespace MarketPlus {
	type ProductType = "Gamepass" | "DeveloperProduct";

	type ProductId = number | string;

	/** The raw receipt Roblox hands to `ProcessReceipt`. */
	interface ReceiptInfo {
		PurchaseId: string;
		PlayerId: number;
		ProductId: number;
		CurrencySpent: number;
		CurrencyType: Enum.CurrencyType;
		PlaceIdWherePurchased: number;
	}

	/** The receipt as it travels through middleware and product callbacks. */
	interface ReceiptPacket {
		/** `undefined` if the buyer already left the server. */
		Player: Player | undefined;
		UserId: number;
		ProductId: ProductId;
		PurchaseId: string;
		CurrencySpent: number;
		CurrencyType: Enum.CurrencyType;
		PlaceIdWherePurchased: number;
		/** Lines pushed here are printed once the packet is processed. */
		Logs: Array<string>;
		Receipt: ReceiptInfo;
	}

	/**
	 * Runs before the product callback. Return a packet to replace the one in
	 * flight, or `undefined` to leave it unchanged. Throwing aborts the
	 * purchase with `NotProcessedYet`.
	 */
	type Middleware = (packet: ReceiptPacket) => ReceiptPacket | undefined;

	/**
	 * Grants the product. Return `false` to reject the purchase
	 * (`NotProcessedYet`); anything else counts as granted.
	 */
	type ProductCallback = (packet: ReceiptPacket) => boolean | undefined;

	interface MarketObject {
		/** Whether economy/custom events are sent to AnalyticsService. */
		Analytics: boolean;
		/** Prompts each target to buy the product. Gamepasses already owned are skipped. */
		PromptPurchaseAsync(Targets: Array<Player>, Type: ProductType, ID: ProductId): void;
		/** Registers the handler that grants a product when purchased. */
		RegisterProduct(Type: ProductType, ID: ProductId, Callback: ProductCallback): void;
		/** Installs a middleware. Only one is held at a time — the last call wins. */
		UseMiddleware(Middleware: Middleware): void;
		/**
		 * Takes over `MarketplaceService.ProcessReceipt`. Process-wide and
		 * idempotent: only the first caller in the server wins.
		 */
		UseIncoming(): void;
		/** Purchases of `ID` this session, or the total across all products when omitted. */
		GetPurchaseCount(Player: Player, ID?: ProductId): number;
		/** Cached where possible; falls back to `UserOwnsGamePassAsync`. */
		OwnsGamepass(Player: Player, ID: ProductId): boolean;
	}
}

interface MarketPlusModule {
	/**
	 * Creates a market object and starts tracking the players in the server.
	 *
	 * Declared as a property, not a method — the Luau defines it with a dot.
	 */
	new: (UseAnalytics: boolean) => MarketPlus.MarketObject;
}

declare const MarketPlus: MarketPlusModule;

export = MarketPlus;
