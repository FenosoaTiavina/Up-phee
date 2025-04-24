const std = @import("std");
const builtin = std.builtin;
const expect = std.testing.expect;
const mem = std.mem;

///References: https://en.wikipedia.org/wiki/Quicksort
pub fn quicksort(comptime T: type, A: []T, lo: usize, hi: usize, comptime lessThanFn: fn (lhs: T, rhs: T) bool) void {
    if (lo < hi) {
        const p = partition(T, A, lo, hi, lessThanFn);
        quicksort(T, A, lo, @min(p, p -% 1), lessThanFn);
        quicksort(T, A, p + 1, hi, lessThanFn);
    }
}

pub fn partition(comptime T: type, A: []T, lo: usize, hi: usize, comptime lessThanFn: fn (lhs: T, rhs: T) bool) usize {
    //Pivot can be chosen otherwise, for example try picking the first or random
    //and check in which way that affects the performance of the sorting
    const pivot = A[hi];
    var i = lo;
    var j = lo;
    while (j < hi) : (j += 1) {
        if (lessThanFn(A[j], pivot)) {
            mem.swap(T, &A[i], &A[j]);
            i = i + 1;
        }
    }
    mem.swap(T, &A[i], &A[hi]);
    return i;
}
