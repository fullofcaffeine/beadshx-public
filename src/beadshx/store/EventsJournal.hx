package beadshx.store;

import haxe.Int64;

/** One bd_events_journal row as upstream readEventsRowsInTx scans it; a NULL payload is empty. */
typedef EventsJournalRow = {
	final seq:Int64;

	/** The stored time as RFC 3339 in UTC, or the driver text when no layout parses it. */
	final ts:String;

	final op:String;
	final issueId:String;
	final issueJson:String;
	final depJson:String;
	final commentJson:String;
}

/** upstream journalops.TruncatedError: the window a pruned-past checkpoint can still read. */
typedef EventsJournalWindow = {
	final since:Int64;
	final floor:Int64;
	final head:Int64;
}

/** A journal read: the rows after the checkpoint, the retained window, or no Haxe-owned route. */
enum EventsJournalRead {
	JournalRecords(rows:Array<EventsJournalRow>);
	JournalTruncated(window:EventsJournalWindow);
	JournalRouteUnavailable;
}

/** journalops.TruncatedError.Error(). */
function eventsTruncatedMessage(window:EventsJournalWindow):String {
	final since = Int64.toStr(window.since);
	final floor = Int64.toStr(window.floor);
	return 'events journal truncated: checkpoint ${since} is below the retained window [${floor}..${Int64.toStr(window.head)}]; '
		+ 'records ${Int64.toStr(window.since + 1)}..${Int64.toStr(window.floor - 1)} were pruned';
}

/**
	Upstream ComputeEventsTruncation: the rows must continue the checkpoint without a hole.
	The head is read only when they do not start right after it or skip a sequence number.
**/
function eventsTruncation(since:Int64, rows:Array<EventsJournalRow>, readHead:() -> StoreResult<Int64>):StoreResult<Null<EventsJournalWindow>> {
	function window(checkpoint:Int64, floor:Int64):StoreResult<Null<EventsJournalWindow>> {
		return switch readHead() {
			case Failure(message): Failure(message);
			case Success(head): Success({since: checkpoint, floor: floor, head: head});
		};
	}
	// No rows: caught up, or the floor is one past a head that nothing below it survived.
	if (rows.length == 0)
		return switch readHead() {
			case Failure(message): Failure(message);
			case Success(head): since >= head ? Success(null) : Success({since: since, floor: head + 1, head: head});
		};
	final first:EventsJournalRow = rows[0];
	if (first.seq != since + 1)
		return window(since, first.seq);
	for (index in 1...rows.length) {
		final previous:EventsJournalRow = rows[index - 1];
		final current:EventsJournalRow = rows[index];
		if (current.seq != previous.seq + 1)
			return window(previous.seq, current.seq);
	}
	return Success(null);
}
