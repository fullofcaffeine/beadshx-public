package beadshx.store;

/** Rare issue fields loaded only for the human long-detail projection. */
typedef IssueLongFields = {
	final isBlocked:Bool;
	final leaseExpiresAt:String;
	final heartbeatAt:String;
	final leaseGrantedNode:String;
	final compactionLevel:Int;
	final compactedAt:String;
	final compactedAtCommit:String;
	final originalSize:Int;
	final sender:String;
	final ephemeral:Bool;
	final noHistory:Bool;
	final storageClass:String;
	final pinned:Bool;
	final template:Bool;
	final bondedFrom:Array<IssueBondReference>;
	final awaitType:String;
	final awaitId:String;
	final timeout:String;
	final timeoutNanos:JsonInteger;
	final waiters:Array<String>;
	final sourceFormula:String;
	final sourceLocation:String;
	final workType:String;
	final eventKind:String;
	final actor:String;
	final target:String;
	final payload:String;
}
