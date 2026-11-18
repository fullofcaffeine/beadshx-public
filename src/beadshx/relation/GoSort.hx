package beadshx.relation;

import haxe.Int64;

/** The two callbacks Go's sort.Slice gives pdqsort: compare and swap the elements at two indexes. */
typedef GoLessSwap = {
	final less:(Int, Int) -> Bool;
	final swap:(Int, Int) -> Void;
}

/** The order that choosePivot sees around its pivot. */
private enum SortedHint {
	UnknownHint;
	IncreasingHint;
	DecreasingHint;
}

/**
	Sorts `values` exactly as Go's sort.Slice does, equal elements included.

	sort.Slice is not stable. For more than 12 elements it runs pdqsort, and where
	equal elements end depends on its pivots, pattern breaking and partitions. The
	algorithm has no randomness, so one input order always gives one result. This
	port follows each step of zsortfunc.go in the pinned Go toolchain to give the
	same result. Like the closure upstream passes, `less` compares the elements
	that are at the two indexes when it is called.
**/
function goSortSlice<T>(values:Array<T>, less:(T, T) -> Bool):Void {
	final data:GoLessSwap = {
		less: (i, j) -> {
			final left:T = values[i];
			final right:T = values[j];
			return less(left, right);
		},
		swap: (i, j) -> {
			final left:T = values[i];
			final right:T = values[j];
			values[i] = right;
			values[j] = left;
		}
	};
	goPdqsort(data, 0, values.length, bitLength(values.length));
}

/**
	Go's pdqsort_func over the indexes [a, b). `limit` is the number of bad pivots
	allowed before heapsort takes over; sort.Slice starts with bits.Len(length).
**/
function goPdqsort(data:GoLessSwap, start:Int, end:Int, limit:Int):Void {
	final maxInsertion = 12;
	var a = start;
	var b = end;
	var badPivotsLeft = limit;
	var wasBalanced = true;
	var wasPartitioned = true;
	while (true) {
		final length = b - a;
		if (length <= maxInsertion) {
			insertionSort(data, a, b);
			return;
		}
		if (badPivotsLeft == 0) {
			heapSort(data, a, b);
			return;
		}
		if (!wasBalanced) {
			breakPatterns(data, a, b);
			badPivotsLeft--;
		}
		final choice = choosePivot(data, a, b);
		var pivot = choice.pivot;
		var hint = choice.hint;
		if (hint == DecreasingHint) {
			reverseRange(data, a, b);
			pivot = (b - 1) - (pivot - a);
			hint = IncreasingHint;
		}
		if (wasBalanced && wasPartitioned && hint == IncreasingHint && partialInsertionSort(data, a, b))
			return;
		if (a > 0 && !data.less(a - 1, pivot)) {
			a = partitionEqual(data, a, b, pivot);
			continue;
		}
		final split = partition(data, a, b, pivot);
		wasPartitioned = split.alreadyPartitioned;
		final leftLength = split.mid - a;
		final rightLength = b - split.mid;
		final balanceThreshold = Std.int(length / 8);
		if (leftLength < rightLength) {
			wasBalanced = leftLength >= balanceThreshold;
			goPdqsort(data, a, split.mid, badPivotsLeft);
			a = split.mid + 1;
		} else {
			wasBalanced = rightLength >= balanceThreshold;
			goPdqsort(data, split.mid + 1, b, badPivotsLeft);
			b = split.mid;
		}
	}
}

/** Go's bits.Len: the number of bits that a non-negative value needs; 0 for 0. */
private function bitLength(value:Int):Int {
	var bits = 0;
	var rest = value;
	while (rest > 0) {
		bits++;
		rest >>= 1;
	}
	return bits;
}

private function insertionSort(data:GoLessSwap, a:Int, b:Int):Void {
	for (i in a + 1...b) {
		var j = i;
		while (j > a && data.less(j, j - 1)) {
			data.swap(j, j - 1);
			j--;
		}
	}
}

private function siftDown(data:GoLessSwap, lo:Int, hi:Int, first:Int):Void {
	var root = lo;
	while (true) {
		var child = 2 * root + 1;
		if (child >= hi)
			return;
		if (child + 1 < hi && data.less(first + child, first + child + 1))
			child++;
		if (!data.less(first + root, first + child))
			return;
		data.swap(first + root, first + child);
		root = child;
	}
}

private function heapSort(data:GoLessSwap, a:Int, b:Int):Void {
	final hi = b - a;
	var i = Std.int((hi - 1) / 2);
	while (i >= 0) {
		siftDown(data, i, hi, a);
		i--;
	}
	i = hi - 1;
	while (i >= 0) {
		data.swap(a, a + i);
		siftDown(data, 0, i, a);
		i--;
	}
}

/** Go's partition_func: the pivot's new index, and whether nothing had to move. */
private function partition(data:GoLessSwap, a:Int, b:Int, pivot:Int):{mid:Int, alreadyPartitioned:Bool} {
	data.swap(a, pivot);
	var i = a + 1;
	var j = b - 1;
	while (i <= j && data.less(i, a))
		i++;
	while (i <= j && !data.less(j, a))
		j--;
	if (i > j) {
		data.swap(j, a);
		return {mid: j, alreadyPartitioned: true};
	}
	data.swap(i, j);
	i++;
	j--;
	while (true) {
		while (i <= j && data.less(i, a))
			i++;
		while (i <= j && !data.less(j, a))
			j--;
		if (i > j)
			break;
		data.swap(i, j);
		i++;
		j--;
	}
	data.swap(j, a);
	return {mid: j, alreadyPartitioned: false};
}

private function partitionEqual(data:GoLessSwap, a:Int, b:Int, pivot:Int):Int {
	data.swap(a, pivot);
	var i = a + 1;
	var j = b - 1;
	while (true) {
		while (i <= j && !data.less(a, i))
			i++;
		while (i <= j && data.less(a, j))
			j--;
		if (i > j)
			break;
		data.swap(i, j);
		i++;
		j--;
	}
	return i;
}

/** Go's partialInsertionSort_func, including its shift-left loop that stops at index 1 rather than at `a`. */
private function partialInsertionSort(data:GoLessSwap, a:Int, b:Int):Bool {
	final maxSteps = 5;
	final shortestShifting = 50;
	var i = a + 1;
	for (_ in 0...maxSteps) {
		while (i < b && !data.less(i, i - 1))
			i++;
		if (i == b)
			return true;
		if (b - a < shortestShifting)
			return false;
		data.swap(i, i - 1);
		if (i - a >= 2) {
			var j = i - 1;
			while (j >= 1 && data.less(j, j - 1)) {
				data.swap(j, j - 1);
				j--;
			}
		}
		if (b - i >= 2) {
			var j = i + 1;
			while (j < b && data.less(j, j - 1)) {
				data.swap(j, j - 1);
				j++;
			}
		}
	}
	return false;
}

/** Go's breakPatterns_func with its xorshift generator, seeded by the length. */
private function breakPatterns(data:GoLessSwap, a:Int, b:Int):Void {
	final length = b - a;
	if (length < 8)
		return;
	var random = Int64.ofInt(length);
	final mask = (1 << bitLength(length)) - 1;
	final middle = a + Std.int(length / 4) * 2;
	for (index in middle - 1...middle + 2) {
		random = random ^ (random << 13);
		random = random ^ (random >>> 7);
		random = random ^ (random << 17);
		var other = random.low & mask;
		if (other >= length)
			other -= length;
		data.swap(index, a + other);
	}
}

/** Go's choosePivot_func: a static, median-of-three or Tukey ninther pivot, and the order it saw. */
private function choosePivot(data:GoLessSwap, a:Int, b:Int):{pivot:Int, hint:SortedHint} {
	final shortestNinther = 50;
	final maxSwaps = 4 * 3;
	final length = b - a;
	var swaps = 0;
	function median(first:Int, second:Int, third:Int):Int {
		var low = first;
		var middle = second;
		var high = third;
		if (data.less(middle, low)) {
			swaps++;
			final held = low;
			low = middle;
			middle = held;
		}
		if (data.less(high, middle)) {
			swaps++;
			final held = middle;
			middle = high;
			high = held;
		}
		if (data.less(middle, low)) {
			swaps++;
			middle = low;
		}
		return middle;
	}
	final quarter = Std.int(length / 4);
	var i = a + quarter;
	var j = a + quarter * 2;
	var k = a + quarter * 3;
	if (length >= 8) {
		if (length >= shortestNinther) {
			i = median(i - 1, i, i + 1);
			j = median(j - 1, j, j + 1);
			k = median(k - 1, k, k + 1);
		}
		j = median(i, j, k);
	}
	return {pivot: j, hint: swaps == 0 ? IncreasingHint : swaps == maxSwaps ? DecreasingHint : UnknownHint};
}

private function reverseRange(data:GoLessSwap, a:Int, b:Int):Void {
	var i = a;
	var j = b - 1;
	while (i < j) {
		data.swap(i, j);
		i++;
		j--;
	}
}
