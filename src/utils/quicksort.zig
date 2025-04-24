const std = @import("std");
const mem = std.mem;

///References: https://en.wikipedia.org/wiki/Quicksort
pub fn quicksort(comptime T: type, A: *[]T, lo: usize, hi: usize, comptime lessThanFn: fn (lhs: T, rhs: T) bool) void {
    if (lo < hi and lo >= 0 and hi >= 0) {
        const p = partition(T, A, lo, hi, lessThanFn);
        quicksort(T, A, lo, p - 1, lessThanFn);
        quicksort(T, A, p + 1, hi, lessThanFn);
    }
}

pub fn partition(comptime T: type, A: *[]T, lo: usize, hi: usize, comptime lessThanFn: fn (lhs: T, rhs: T) bool) usize {
    //Pivot can be chosen otherwise, for example try picking the first or random
    //and check in which way that affects the performance of the sorting
    const pivot = A.*[hi];
    var i = lo;
    var j = lo;
    while (j <= hi) : (j += 1) {
        if (lessThanFn(A.*[j], pivot)) {
            i = i + 1;
            mem.swap(T, &A.*[i], &A.*[j]);
        }
    }
    mem.swap(T, &A.*[i], &A.*[hi]);
    return i;
}
