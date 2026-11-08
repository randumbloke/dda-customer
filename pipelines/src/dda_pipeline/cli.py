"""Command line: generate synthetic files, run a pipeline stage, create AT fixtures, validate."""

from __future__ import annotations

import argparse
import logging
import sys

from dda_pipeline import generator
from dda_pipeline.config import RuntimeConfig, load_steps, pipeline_home


def _generate(args: argparse.Namespace) -> int:
    cfg = generator.GeneratorConfig(
        business=args.business,
        seed=args.seed,
        customers=args.customers,
        inject_failures=args.inject_failures,
    )
    files = generator.generate(cfg)
    if args.bucket:
        written = generator.write_gcs(files, args.bucket)
    else:
        written = generator.write_local(files, args.out_dir)
    for w in written:
        print(w)
    return 0


def _run(args: argparse.Namespace) -> int:
    from dda_pipeline.runner import run_stage

    cfg = RuntimeConfig.from_env()
    home = pipeline_home()
    result = run_stage(cfg, load_steps(home), args.stage, home)
    for scan, state in result.scans.items():
        print(f"{scan}: {state}")
    return 0 if result.ok else 1


def _fixtures(args: argparse.Namespace) -> int:
    from dda_pipeline.runner import run_fixture

    cfg = RuntimeConfig.from_env()
    home = pipeline_home()
    run_fixture(cfg, load_steps(home), args.at, home)
    return 0


def _validate(args: argparse.Namespace) -> int:
    from dda_pipeline.validate import validate_repository

    errors = validate_repository(args.root)
    for e in errors:
        print(e, file=sys.stderr)
    print(f"{'FAILED' if errors else 'OK'}: {len(errors)} error(s)")
    return 1 if errors else 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(prog="dda-pipeline", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    g = sub.add_parser("generate", help="write synthetic CSV files (fixed seed)")
    g.add_argument("--business", required=True, choices=sorted(generator.GENERATORS))
    g.add_argument("--seed", type=int, default=generator.DEFAULT_SEED)
    g.add_argument("--customers", type=int, default=generator.DEFAULT_CUSTOMERS)
    g.add_argument("--inject-failures", action="store_true", help="AT-15/AT-17: break critical rules")
    dest = g.add_mutually_exclusive_group(required=True)
    dest.add_argument("--bucket", help="landing bucket, for example kcdda-core-dwh-dev-customer-landing")
    dest.add_argument("--out-dir", help="local directory instead of the bucket")
    g.set_defaults(func=_generate)

    r = sub.add_parser("run", help="run one stage (configuration from DDA_* environment variables)")
    r.add_argument("--stage", required=True, choices=["ingest", "build"])
    r.set_defaults(func=_run)

    f = sub.add_parser("fixtures", help="create an acceptance-test fixture table")
    f.add_argument("--at", required=True)
    f.set_defaults(func=_fixtures)

    v = sub.add_parser("validate", help="validate the declarative files against schemas/")
    v.add_argument("--root", default=str(pipeline_home().parent))
    v.set_defaults(func=_validate)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
