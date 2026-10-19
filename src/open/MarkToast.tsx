// After a > or < mark: the suggested destination, read-only, with a shortcut
// to open that page. The app never writes there; the user does (CLAUDE.md 2).
import { useEffect } from "react";
import type { Destination, Mark } from "../data/openItems";
import { t } from "../i18n/en";
import { goUp } from "../pages/nav";
import { navigate } from "../router";

export function openDestination(d: Destination) {
  if (d.flashId) goUp(d.path, d.flashId);
  else navigate(d.path);
}

export function MarkToast({
  mark,
  destination,
  onDone,
}: {
  mark: Mark | null;
  destination: Destination | null;
  onDone: () => void;
}) {
  useEffect(() => {
    const id = window.setTimeout(onDone, 4500);
    return () => window.clearTimeout(id);
  }, [onDone]);
  return (
    <div className="undo-toast mark-toast" role="status">
      {mark && destination ? (
        <>
          <span>
            <b className="mark-glyph">{mark === "migrated" ? ">" : "<"}</b>{" "}
            {t.open.marked[mark]} ·{" "}
            <span className="mark-dest">{destination.label}</span>
          </span>
          <button
            onClick={() => {
              onDone();
              openDestination(destination);
            }}
          >
            {t.open.go}
          </button>
        </>
      ) : (
        <span>{t.open.unmarked}</span>
      )}
    </div>
  );
}
