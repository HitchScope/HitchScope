# Contributing

HitchScope is an open-source SDK backing a commercial product, maintained by a single person. A few things that follow from that:

- Response times on issues and PRs won't be fast — please be patient.
- Small, focused PRs (bug fixes, docs, platform compatibility) are the easiest to review and merge.
- Larger feature proposals are worth opening an issue for first, before writing code, to make sure they fit the SDK's scope (relaying MetricKit data — not session replay, error grouping, or other broader observability surface).

## Development

```bash
swift build
swift test
```

To test changes against a real app on a simulator, see `Example/README.md`.
