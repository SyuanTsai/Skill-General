---
name: verify-data-access-performance
description: Analyze and test database query efficiency with repeated measurements, query counts, and N+1 checks. Use when the user needs to check, review, or fix slow queries, ORM loading behavior, benchmarks, or round-trip growth.
---

# Verify Data-Access Performance

1. Apply this workflow only to performance improvement, benchmarking, query optimization, or N+1 work. Do not add performance tests to unrelated feature changes.
2. Read the repository's testing and database rules before proposing or changing code. Preserve its projection, return-shape, framework, and test-style constraints.
3. Identify the root cause before choosing a fix: unnecessary entities, relationships, or rows; excess round trips; N+1 behavior; unsuitable loading strategy; or missing relevant indexes.
4. Keep functional tests separate from performance tests. Verify result correctness as well as performance behavior.
5. Run multiple measured samples and record:
   - sample count;
   - average, minimum, and maximum execution time;
   - database query count, or not applicable when no database is involved.
6. Complete data seeding before resetting the SQL command counter so Arrange queries are excluded.
7. For N+1 validation, compare at least two result sizes, record query counts for both, and confirm that the count stays fixed or within an explicit bound rather than growing linearly.
8. Do not use elapsed milliseconds as a hard CI threshold. In CI, assert query count, query shape, and result correctness.
9. Mark manual benchmarks skipped by default so normal test runs do not execute them.
10. Report in the user's language the commands, dataset or sample sizes, measurements, query counts, conclusion, and remaining uncertainty.

## Example

```text
User request:
"Verify that this EF Core change removes the N+1 behavior."

Expected workflow:
1. Seed the same dataset before resetting the SQL command counter.
2. Measure at least two result sizes across repeated samples.
3. Record correctness, timing, and query counts for each size.
4. Confirm query count remains fixed or within an explicit bound without using milliseconds as a CI threshold.
```

Example measurement report:

```text
Rows: 10   Samples: 5   Queries: 2   Avg: 18 ms
Rows: 100  Samples: 5   Queries: 2   Avg: 31 ms
Conclusion: query count remains bounded; no N+1 growth observed.
```

## Error Handling

- If measurements are noisy or inconsistent, increase the sample count and report the variance instead of declaring an improvement from a single run.
- If the query counter includes seeding or setup statements, reset it after Arrange and repeat the measurement before drawing a conclusion.
- If query counts grow with result size, treat the N+1 condition as unresolved even when elapsed time appears acceptable.
- If the repository lacks a reliable database test harness, separate what can be validated automatically from what requires a manual benchmark and state the remaining uncertainty.
- If a proposed optimization changes returned data, ordering, tracking semantics, or another functional contract, stop treating it as a performance-only modification and verify correctness first.
