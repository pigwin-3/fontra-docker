"""Export one font from the multi-user database to files.

Usage: python export_job.py PROJECT/FONT FORMAT OUTPUT_DIR

FORMAT is designspace, ufo, fontra, otf, ttf or woff2. The account comes from
the EXPORT_USER and EXPORT_PASSWORD environment variables. Binary formats are
compiled with fontmake the same way as Fontra Pak's "Export as".
"""

import asyncio
import logging
import os
import pathlib
import sys
import tempfile
from contextlib import aclosing

from fontra.backends import newFileSystemBackend
from fontra.backends.copy import copyFont
from fontra.core.classes import DiscreteFontAxis
from fontra.workflow.workflow import Workflow
from fontra_rcjk.backend_mysql import RCJKMySQLBackend
from fontra_rcjk.client_async import RCJKClientAsync
from fontTools.ttLib.woff2 import compress as woff2Compress

ROBOCJK_URL = os.environ.get("ROBOCJK_URL", "https://proxy:9443/")


class GlyphProblems(logging.Handler):
    """Collects the glyphs that fontra-copy had to leave out."""

    def __init__(self):
        super().__init__(level=logging.ERROR)
        self.messages = []

    def emit(self, record):
        self.messages.append(record.getMessage())


async def compileFont(source, destPath):
    # Same steps as Fontra Pak: drop discrete axes, decompose variable
    # components, propagate anchors, then compile with fontmake.
    axes = await source.getAxes()
    discreteAxisNames = [
        axis.name for axis in axes.axes if isinstance(axis, DiscreteFontAxis)
    ]
    steps = []
    if discreteAxisNames:
        steps.append(dict(filter="subset-axes", dropAxisNames=discreteAxisNames))
    steps += [
        dict(filter="decompose-composites", onlyVariableComposites=True),
        dict(filter="propagate-anchors"),
        dict(filter="drop-unreachable-glyphs"),
        dict(
            output="compile-fontmake",
            destination=destPath.name,
            options={"overlaps-backend": "pathops"},
        ),
    ]
    workflow = Workflow(config=dict(steps=steps), parentDir=destPath.parent)
    async with workflow.endPoints(source) as endPoints:
        for output in endPoints.outputs:
            await output.process(destPath.parent)


async def export(fontName, fileFormat, outputDir):
    client = RCJKClientAsync(
        host=ROBOCJK_URL,
        username=os.environ["EXPORT_USER"],
        password=os.environ["EXPORT_PASSWORD"],
    )
    await client.connect()
    try:
        fonts = {
            f"{project}/{font}": uids
            for (project, font), uids in (
                await client.get_project_font_uid_mapping()
            ).items()
        }
        if fontName not in fonts:
            sys.exit(f"No font {fontName!r} for this account")
        source = RCJKMySQLBackend.fromRCJKClient(client, fonts[fontName][1])
        baseName = fontName.split("/", 1)[1]
        async with aclosing(source):
            if fileFormat == "ufo" and (await source.getAxes()).axes:
                sys.exit(
                    "A UFO holds a single master, but this font has axes. "
                    "Choose Designspace + UFO instead."
                )
            if fileFormat in {"designspace", "ufo", "fontra"}:
                # Glyphs that can't be read are left out and listed in
                # export-problems.txt instead of failing the whole export.
                problems = GlyphProblems()
                logging.getLogger("fontra.backends.copy").addHandler(problems)
                dest = newFileSystemBackend(outputDir / f"{baseName}.{fileFormat}")
                async with aclosing(dest):
                    await copyFont(source, dest, continueOnError=True)
                if problems.messages:
                    (outputDir / "export-problems.txt").write_text(
                        "These glyphs could not be exported:\n\n"
                        + "\n".join(problems.messages)
                        + "\n"
                    )
            elif fileFormat in {"otf", "ttf"}:
                await compileFont(source, outputDir / f"{baseName}.{fileFormat}")
            elif fileFormat == "woff2":
                with tempfile.TemporaryDirectory() as tmpDir:
                    ttfPath = pathlib.Path(tmpDir) / f"{baseName}.ttf"
                    await compileFont(source, ttfPath)
                    woff2Compress(str(ttfPath), str(outputDir / f"{baseName}.woff2"))
            else:
                sys.exit(f"Unknown format {fileFormat!r}")
    finally:
        await client.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(name)s %(levelname)s %(message)s")
    fontName, fileFormat, outputDir = sys.argv[1:]
    asyncio.run(export(fontName, fileFormat, pathlib.Path(outputDir)))
