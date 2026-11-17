import beadshx.store.EmbeddedCgoStore;
import beadshx.store.EmbeddedStoreAccess;
import beadshx.store.EmbeddedScalarIssueDetailsReader;
import beadshx.store.GoReadonlyStore;
import beadshx.store.IssueDetails;
import beadshx.store.IssueDetailsRequest;

/** The native test owns a disposable database; these calls exercise real authored readers. */
@:goNative
class Main {
	public static function observeEmbeddedComments(beadsDir:String, id:String, include:Bool, viaStore:Bool):String {
		final request:IssueDetailsRequest = {includeDependents: false, includeComments: include, briefDependencies: false};
		EmbeddedStoreAccess.install(new EmbeddedCgoStore());
		if (viaStore)
			return switch new GoReadonlyStore().issueDetails(beadsDir, id, request, false) {
				case Failure(message): failure(message);
				case Success(DetailsMissing): failure("missing");
				case Success(DetailsFound(details)): encode(details);
			};
		return switch new EmbeddedScalarIssueDetailsReader(beadsDir).read(id, request) {
			case EmbeddedScalarDetailsFailure(message): failure(message);
			case EmbeddedScalarDetailsMissing: failure("missing");
			case EmbeddedScalarDetailsRequireRelations: failure("requires relations");
			case EmbeddedScalarDetailsFound(details): encode(details);
		};
	}

	static function encode(details:IssueDetails):String {
		final comments = [
			for (c in details.comments)
				{
					id: c.id,
					author: c.author,
					text: c.text,
					createdAt: c.createdAt
				}
		];
		return '{"error":"","count":${details.commentCount.wireValue()},"omitted":${details.commentsOmitted},"comments":${haxe.Json.stringify(comments)}}';
	}

	static function failure(message:String):String {
		return haxe.Json.stringify({
			error: message,
			count: 0,
			omitted: false,
			comments: []
		});
	}

	static function main():Void {
		if (Sys.args().indexOf("--embedded-comment-observer") >= 0)
			Sys.println(observeEmbeddedComments("", "", false, false));
	}
}
