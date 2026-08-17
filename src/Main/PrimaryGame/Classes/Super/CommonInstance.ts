//-------------------------------------------------------------------- MODULES
import Signal from "@shared/signal";
//-------------------------------------------------------------------- Registry
const Ancestry = new Map<string, string | undefined>()

export function RegisterClass(Name: string, Parent?: string) {
    Ancestry.set(Name, Parent)
}

RegisterClass("CommonInstance", undefined)
//-------------------------------------------------------------------- CommonInstance
export class CommonInstance {
    public readonly ClassName: string = "CommonInstance";
    public readonly Destroying: Signal.Signal<[]> = Signal.new<[]>("Serial");
    public Destroyed = false;

    public static New<T extends CommonInstance, A extends Array<unknown>>(
        this: new (...args: A) => T,
        ...args: A
    ): T {
        const Built = new this(...args)

        Built.Ready()

        return Built
    }

    public Ready(): void {}

    public IsA(ClassName: string): boolean {
        let Current: string | undefined = this.ClassName

        while (Current !== undefined) {
            if (Current === ClassName) {
                return true
            }

            Current = Ancestry.get(Current)
        }

        return false
    }

    protected OnDestroyed(): void {}

    public Destroy(): void {
        if (this.Destroyed) {
            return
        }

        this.Destroyed = true

        const [Ok, Err] = pcall(() => this.OnDestroyed())

        if (!Ok) {
            task.spawn(() => error(Err))
        }

        this.Destroying.Fire()
        this.Destroying.Destroy()
    }
}
