package beadshx.identity;

/** Resolves the actor used by assignee-scoped read commands. */
interface ActorPort {
	function resolve(explicit:String):String;
}
