import { describe, expect, it } from 'vitest';
import { type Interval, intersect, invert, merge } from './intervals.js';

const iv = (start: number, end: number): Interval => ({ start, end });

describe('merge', () => {
  it('coalesces touching intervals', () => {
    expect(merge([iv(0, 10), iv(10, 20)])).toEqual([iv(0, 20)]);
  });

  it('coalesces overlapping intervals', () => {
    expect(merge([iv(0, 10), iv(5, 20)])).toEqual([iv(0, 20)]);
  });

  it('keeps disjoint intervals separate', () => {
    expect(merge([iv(0, 10), iv(20, 30)])).toEqual([iv(0, 10), iv(20, 30)]);
  });

  it('swallows a nested interval', () => {
    expect(merge([iv(0, 100), iv(20, 30)])).toEqual([iv(0, 100)]);
  });

  it('sorts before coalescing', () => {
    expect(merge([iv(20, 30), iv(0, 10), iv(9, 21)])).toEqual([iv(0, 30)]);
  });

  it('returns [] for []', () => {
    expect(merge([])).toEqual([]);
  });

  it('does not mutate its input', () => {
    const input = [iv(20, 30), iv(0, 10), iv(5, 25)];
    const before = JSON.stringify(input);
    merge(input);
    expect(JSON.stringify(input)).toBe(before);
  });
});

describe('invert', () => {
  it('returns the whole horizon when nothing is busy', () => {
    expect(invert([], 0, 1000)).toEqual([iv(0, 1000)]);
  });

  it('returns nothing when the horizon is fully busy', () => {
    expect(invert([iv(0, 1000)], 0, 1000)).toEqual([]);
    expect(invert([iv(-500, 1500)], 0, 1000)).toEqual([]);
  });

  it('handles busy straddling the left edge', () => {
    expect(invert([iv(-100, 50)], 0, 1000)).toEqual([iv(50, 1000)]);
  });

  it('handles busy straddling the right edge', () => {
    expect(invert([iv(900, 2000)], 0, 1000)).toEqual([iv(0, 900)]);
  });

  it('handles busy in the middle', () => {
    expect(invert([iv(200, 300), iv(600, 700)], 0, 1000)).toEqual([iv(0, 200), iv(300, 600), iv(700, 1000)]);
  });

  it('handles busy entirely outside the horizon', () => {
    expect(invert([iv(2000, 3000)], 0, 1000)).toEqual([iv(0, 1000)]);
    expect(invert([iv(-3000, -2000)], 0, 1000)).toEqual([iv(0, 1000)]);
  });

  it('handles busy that exactly fills the horizon edges', () => {
    expect(invert([iv(0, 400)], 0, 1000)).toEqual([iv(400, 1000)]);
    expect(invert([iv(400, 1000)], 0, 1000)).toEqual([iv(0, 400)]);
  });
});

describe('intersect', () => {
  it('returns the nested interval', () => {
    expect(intersect([iv(0, 100)], [iv(20, 50)])).toEqual([iv(20, 50)]);
  });

  it('returns the partial overlap', () => {
    expect(intersect([iv(0, 50)], [iv(30, 80)])).toEqual([iv(30, 50)]);
  });

  it('returns nothing for touching-but-not-overlapping intervals', () => {
    expect(intersect([iv(0, 50)], [iv(50, 80)])).toEqual([]);
  });

  it('returns nothing for disjoint intervals', () => {
    expect(intersect([iv(0, 10)], [iv(20, 30)])).toEqual([]);
  });

  it('returns nothing when either side is empty', () => {
    expect(intersect([], [iv(0, 10)])).toEqual([]);
    expect(intersect([iv(0, 10)], [])).toEqual([]);
    expect(intersect([], [])).toEqual([]);
  });

  it('walks both lists', () => {
    const a = [iv(0, 100), iv(200, 300), iv(400, 500)];
    const b = [iv(50, 250), iv(260, 450)];
    expect(intersect(a, b)).toEqual([iv(50, 100), iv(200, 250), iv(260, 300), iv(400, 450)]);
  });

  it('is symmetric', () => {
    const a = [iv(0, 100), iv(200, 300)];
    const b = [iv(50, 250)];
    expect(intersect(a, b)).toEqual(intersect(b, a));
  });
});
