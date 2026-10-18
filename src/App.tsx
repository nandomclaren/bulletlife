import { useEffect } from 'react';
import { restoreScroll, usePath } from './router';
import { ProtoChooser, ProtoPage } from './proto/ProtoPage';
import { SpikePage } from './spike/SpikePage';
import { SampleDay, SampleMonth } from './spike/SamplePages';

export function App() {
  const path = usePath();
  useEffect(restoreScroll, [path]);

  const month = path.match(/^\/month\/(\d{4}-\d{2})$/);
  if (month) return <SampleMonth ym={month[1]} />;
  const day = path.match(/^\/day\/(\d{4}-\d{2}-\d{2})$/);
  if (day) return <SampleDay iso={day[1]} />;
  const proto = path.match(/^\/proto\/(a|b)$/);
  if (proto) return <ProtoPage key={proto[1]} kind={proto[1] as 'a' | 'b'} />;
  if (path === '/check') return <SpikePage />;
  return <ProtoChooser />;
}
