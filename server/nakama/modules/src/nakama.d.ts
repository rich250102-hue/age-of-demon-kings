// Déclarations minimales de l'API serveur Nakama utilisées par ce module.
declare namespace nkruntime {
  interface Context { userId: string; username: string; }
  interface Logger { info(msg: string, ...args: any[]): void; warn(msg: string, ...args: any[]): void; error(msg: string, ...args: any[]): void; }
  interface StorageReadRequest { collection: string; key: string; userId: string; }
  interface StorageObject { collection: string; key: string; userId: string; value: any; version: string; }
  interface StorageWriteRequest { collection: string; key: string; userId: string; value: any; version?: string; permissionRead?: number; permissionWrite?: number; }
  interface Account { user: { id: string; metadata: { [key: string]: any } }; }
  interface Nakama {
    storageRead(reads: StorageReadRequest[]): StorageObject[];
    storageWrite(writes: StorageWriteRequest[]): any[];
    accountGetId(userId: string): Account;
  }
  interface Initializer { registerRpc(id: string, fn: RpcFunction): void; }
  type RpcFunction = (ctx: Context, logger: Logger, nk: Nakama, payload: string) => string;
  type InitModule = (ctx: Context, logger: Logger, nk: Nakama, initializer: Initializer) => void;
}
