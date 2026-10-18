// Auto-detected values per check, collected for the copyable report.
import { useEffect } from 'react';

const facts = new Map<string, Map<string, string>>();

export function useFact(checkId: string, label: string, value: string | null | undefined) {
  useEffect(() => {
    if (value == null) return;
    if (!facts.has(checkId)) facts.set(checkId, new Map());
    facts.get(checkId)!.set(label, value);
  }, [checkId, label, value]);
}

export function getFacts(checkId: string): Array<[string, string]> {
  return [...(facts.get(checkId) ?? new Map()).entries()];
}

export function deviceLabel() {
  const ua = navigator.userAgent;
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'iPad';
  if (/Macintosh/.test(ua)) return 'Mac';
  return 'Other';
}

export function isStandalone() {
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}
