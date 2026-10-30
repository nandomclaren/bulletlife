# CLAUDE.md — Bullet Life

> Leia este arquivo inteiro antes de escrever código. Ele é a fonte única de verdade do produto.
> Trabalhe **uma fase por vez** (seção 13), começando pela **Fase 0 (spike)**. Ao final de cada fase, rode os critérios de aceite e resuma ao Fernando o que ficou pronto e o que ficou em aberto.
> **Idiomas (decisão do Fernando): este documento fica em português, mas a UI do app é 100% em inglês.** Nenhum texto visível ao usuário em português: rótulos, botões, menus, ajustes, mensagens vazias, faixas, painel de pendências, nomes de temas, nomes de meses e dias (via `Intl` com locale `en`), `aria-label`, nome e descrição no manifest. Código, comentários, nomes de variáveis e commits também em **inglês**. Mantenha as strings da UI fora dos componentes (arquivo único de strings, ex.: `src/i18n/en.ts`), para permitir outros idiomas na versão comercial. **Os textos em português entre aspas neste documento são referências para o Fernando, não os textos finais da UI:** use o glossário da seção 8.1.

---

## 1. O que estamos construindo

Um web app instalável como **PWA no Mac e no iPhone** para praticar no digital o método de journaling criado por **Ryder Carroll** (o *Bullet Journal®*). Uso pessoal por enquanto (dono: Fernando), mas com decisões de arquitetura que permitam uma versão comercial depois.

O método foi criado no papel para gerar **intencionalidade**. O app não tenta substituir isso por automação: ele é o caderno, com a ajuda de um assistente que **lembra, mas não faz**.

**Nome do produto: Bullet Life** (escolhido pelo Fernando). Use `bullet-life` como nome de pasta, pacote e repositório.

Regras de nome e marca:
- Na **UI, no manifest, na loja e em qualquer texto de marketing, não use "Bullet Journal" nem "BuJo"** (marcas registradas da Lightcage, LLC; ver seção 14). Termos genéricos como "caderno", "log" e "migração" são ok. Este documento pode citar o método porque é interno.
- Não usar "Bear" nem nenhum nome, logo, ícone, fonte proprietária ou nome de tema do app Bear (ver seção 8).
- Não copiar nome, textos, assets ou identidade de nenhum app concorrente. Os layouts de referência da seção 3.6 são só inspiração de estrutura.

---

## 2. Princípios inegociáveis (invariantes)

Qualquer funcionalidade que viole um destes itens está errada, mesmo que pareça conveniente.

1. **Fricção intencional é uma funcionalidade.** O app **nunca** cria, move, copia, conclui, cancela, migra ou apaga entradas por conta própria. Toda mudança parte de um gesto individual do usuário sobre uma entrada específica.
   - **Migrar = marcar a origem** com `>` ou `<` **e o usuário escrever o item no destino com as próprias mãos.** O app não cria a cópia.
   - Sem ações em massa ("migrar todas", "cancelar todas", "marcar tudo").
   - Sem rollover automático de tarefas entre dias, semanas ou meses.
   - Sem arrastar/colar entradas de um log para outro, e sem botão "copiar texto" dentro do painel de pendências. Isso retiraria a fricção de reescrever.
   - Reordenar e indentar dentro da **mesma página** é permitido (não é migração).
   - **Exceção autorizada pelo Fernando: listas numeradas.** Linhas que começam com número (`1. `, `2) `) são renumeradas pelo app quando a estrutura da lista muda (Enter, apagar, juntar linhas, indentar/desindentar, colar). Enter num item numerado já começa a linha com o próximo número; Enter num item vazio encerra a lista. Nada além do número é alterado. **Override do usuário vence:** um número digitado fora da sequência (ex.: `10.` depois de `2.`) é mantido e os seguintes contam a partir dele (`11.`, `12.`).
2. **Auxiliar sem fazer.** Os recursos de lembrete (faixa de montagem, painel de pendências, fechar o dia) **mostram e consultam**. A única escrita permitida a partir deles são marcações individuais de estado (seção 4.3).
3. **Página livre.** O usuário pode escrever o que quiser: entradas com bullet, texto corrido, títulos, subitens. Nenhum ritual é obrigatório, bloqueia a edição ou impede pular etapas.
4. **Local-first.** Tudo funciona offline. Leitura e escrita sempre no dispositivo; o sync é um complemento.
5. **Captura em segundos.** Abrir o app deve deixar o usuário digitando na página do dia (log ativo mais fino) sem passos extras.
6. **Os dados são do usuário.** Exportar/copiar qualquer tela deve levar poucos toques (seção 7).
7. **Mínimo de criação automática de páginas.** Páginas são criadas de forma preguiçosa, na primeira escrita ou por ação explícita ("Montar semana"). Nunca crie páginas vazias em segundo plano. Navegar para uma página que ainda não existe **não a cria** (seção 5.1). A estrutura de layout do Monthly (título do mês e dias) e do Ano (12 meses) é **renderizada a partir da data**, não gravada como entradas; só o que o usuário escreve é gravado.

---

## 3. O método dentro do app

### 3.1 Módulos

- **Index**: sempre ativo, com busca global (Fase 5). Mostra o **Year atual** (fixo no topo) e as **Collections**. *Decisão do Fernando: não listar dias/semanas/meses escritos (poluía); Today e o calendário ficam no cabeçalho do Index na mesma posição das outras páginas, sem as setas ‹ ›.*
- **Future Log / Ano**: sempre ativo. Uma página por **ano civil** (jan–dez), com os 12 meses em layout fixo (seção 3.6). Na UI aparece como **"Year"**.
- **Monthly Log**: opcional. Página do mês com **layout fixo**: calendário com todos os dias + seção "Month tasks" (seção 3.6).
- **Weekly Log**: opcional. Uma página por semana.
- **Daily Log**: opcional. Uma página por dia.
- **Collections**: páginas livres criadas pelo usuário (ex.: "Waiting For", "Someday/Maybe", projetos). Aparecem no Index.

### 3.2 Logs ativos (configurável)

- Index e Future Log estão sempre ligados.
- O usuário liga **pelo menos 1** entre Monthly, Weekly e Daily. Ou seja, no mínimo 2 módulos ativos contando o Future Log.
- Motivo: migrar precisa de origem e destino. Com um único log de tempo, `>` aponta para o próximo período dele e `<` para o Future Log.
- Configurações dependentes: primeiro dia da semana (padrão: segunda-feira) e formato de data (padrão: DD/MM).
- ~~**Horizonte** / destino sugerido~~ (retirado pelo Fernando: como o app não executa a migração, mostrar um destino só confundia). Ao marcar `>` ou `<`, o app mostra apenas "Migrated"/"Scheduled" com **Undo**. O destino é decidido e escrito pelo usuário.

### 3.3 Bullets clássicos (método original)

| Tipo | Glifo | Estados |
|---|---|---|
| Tarefa | `•` aberta | `×` concluída · `>` migrada · `<` agendada · **riscada** = cancelada |
| Evento | `○` aberto | mesmos estados da tarefa: `×` concluído · `>` migrado · `<` agendado · **riscado** = cancelado (**desligável nos Ajustes**, ver 12) |
| Nota | `–` | sem estados |

Signifiers (à esquerda do bullet): `*` prioridade, `!` inspiração, olho = explorar.

Texto de uma tarefa ou evento concluído fica atenuado; cancelado fica riscado e atenuado. **Notas nunca têm estado.** Eventos têm estado por padrão (o Fernando conclui, cancela e migra eventos como faz com tarefas); o ajuste "Estados em eventos" (seção 12) pode desligar isso, e então eventos se comportam como no método original (sem estado, sem entrar nas pendências).

**Não usar bullets de profundidade (vazado/preenchido por nível).** Seguimos o método original: o glifo indica o **tipo**, não o nível.

### 3.4 Rapid logging por prefixo (no início da linha + espaço)

- `. ` → tarefa
- `o. ` → evento *(com o ponto, para não disparar ao digitar a palavra "o"/"of" no início de uma frase)*
- `- ` → nota
- `* ` antes de um bullet → prioridade
- Os glifos também valem como prefixo (`• `/`· ` tarefa, `○ ` evento, `– `/`— ` nota), porque o Scribble do iPad transforma o ponto escrito em "•". Com o Scribble (texto que chega sem tecla), o prefixo é lido quando a escrita pausa (1,5 s), ao sair da linha ou no Enter, para não atrapalhar as correções que ele faz na hora.
- `# ` → título
- Linha sem prefixo → texto livre

Os prefixos devem ser configuráveis. A conversão de tipo também é possível pelo menu do bullet (seção 6).

### 3.5 Subitens e colapso

- Indentar um item (Tab no Mac; no iPhone, **espaço no início da linha**) torna o item de cima **pai** automaticamente. **Backspace no início da linha** desindenta; no nível 0, um novo Backspace remove o bullet (vira texto livre) e o seguinte junta com a linha de cima.
- Pais exibem um chevron para **colapsar/expandir**; o estado `collapsed` é salvo na entrada.
- **Colapsar nunca afeta exportação, cópia ou busca**: tudo continua incluído (seção 7).
- Nível de aninhamento sem limite rígido (testar até 6 níveis).

### 3.7 Datas com `due:` (pedido do Fernando)

- Escrever `due:` + data em qualquer entrada: `AAAA-MM-DD`, forma curta deste ano (`23/10`; o ajuste de formato de data decide dia ou mês primeiro), ou palavras (`today`, `tomorrow`, `yesterday`, `fri`, `next monday`, `next week`, `in 3 days`).
- Ao terminar a palavra, grava-se `due:AAAA-MM-DD` no texto (uma data escrita como "tomorrow" não pode mudar sozinha) e a UI mostra uma **pílula** com calendário e "Today"/"Tomorrow"/"Yesterday" ou "23 Oct", com cor pela urgência. Tocar na pílula troca a data.
- Tarefas/eventos abertos com data de hoje ou atrasada entram no grupo **Due** do painel Open items, de qualquer página.
- **Ordenar por data só a pedido:** listas de 2+ bullets irmãos com datas fora de ordem oferecem um botão discreto; o app nunca reordena sozinho. Sem data vai para o fim; riscados ordenam como os outros.

### 3.6 Layouts fixos: Monthly e Ano

**Referência visual:** a tela "This Month" do app de Hamish Johnson que o Fernando testou (screenshot dele). Estrutura: rótulo pequeno em versalete com o mês, título grande, e uma lista vertical com **todos os dias do mês**, cada linha com o **número do dia** e a **inicial do dia da semana**, com uma **linha fina divisória entre semanas**. Copiar a *ideia de layout*; **não** copiar textos, assets, nome ou identidade desse app. O Fernando diz que o app dele fez concessões demais e virou "só mais um app de tarefas"; este não deve ir por esse caminho.

**Monthly Log (calendário)**
- Estrutura **renderizada a partir da data**, nunca gravada como entradas: rótulo pequeno em versalete com o mês ("OCTOBER") + título grande ("This Month" no mês corrente; nos outros, "October 2026") + uma linha por dia. É o equivalente digital do adesivo de mês do caderno: poupa o usuário de escrever título e dias à mão.
- **Linha do dia:** coluna do **número** (algarismos tabulares) + coluna da **inicial** do dia da semana em 1 letra em inglês (`Intl` `weekday: 'narrow'`: M T W T F S S com semana começando na segunda; `aria-label` com o nome completo) + área de texto livre. Hoje destacado de forma sutil (número em negrito + pontinho na cor de destaque); fins de semana levemente atenuados. Meses com menos de 31 dias mostram só os dias reais.
- **Divisória fina entre semanas**, respeitando o "primeiro dia da semana" (seção 12). Na divisória, um rótulo muito discreto "Wk 43", **tocável** (leva ao Weekly, seção 5.1).
- **O que se escreve em cada dia (método purista):** frases curtas que resumem o dia, em texto livre (`type = text`). Tarefas e eventos com prefixo continuam possíveis, porque a página é livre, mas o layout **não os estimula** (sem botão "+ task" por dia). Linhas de texto livre **nunca entram nas pendências**. As entradas gravam `slot = 'AAAA-MM-DD'`.
- **Ajuste de espaço para as frases** (decisão do Claude, a pedido do Fernando): a linha tem altura mínima de 44 px. Se o texto não couber em uma linha, (1) reduza a fonte **gradualmente até 85% do tamanho normal (mínimo 14 px)**; (2) se ainda não couber, **quebre a linha e deixe a linha do dia crescer**. **Nunca truncar nem esconder texto.** Número e inicial ficam alinhados ao topo da linha.
- Abaixo (ao lado, no Mac em tela larga, como um caderno aberto) fica a seção **"Month tasks"**: página livre normal (bullets, subitens, estados).

**Ano (Future Log)**
- Uma página por **ano civil**; abre no ano corrente; ‹ › mudam de ano.
- **12 seções**, cada uma com o **nome do mês já escrito** (cabeçalho; mês corrente destacado) e uma **área de escrita bem generosa**: altura mínima confortável (~96 px) que **cresce conforme o conteúdo, sem limite**. Texto livre, bullets, subitens e estados, tudo permitido. As entradas gravam `slot = 'AAAA-MM'`.
- O cabeçalho do mês é **tocável** e abre o Monthly daquele mês (seção 5.1). Cabeçalhos fixos (sticky) ao rolar.
- Roadmap: fotos por mês (seção 14).

---

## 4. Painel de pendências

Resolve o problema do caderno que o digital agrava: no papel você vira as páginas e vê o que ficou esquecido; no digital, as entradas somem em páginas antigas. **O painel mostra tudo que está solto. Ele não resolve nada pelo usuário.**

### 4.1 O que conta como pendente (consulta derivada, nunca armazenada)

- **A. Tarefas e eventos abertos em períodos encerrados**: `type = task` (ou `type = event`, **somente se "Estados em eventos" estiver ligado**), `state = open`, em Daily/Weekly/Monthly cujo `periodEnd` já passou. (Ficaram com `•` ou `○` e nunca foram concluídos, migrados ou cancelados.) Notas nunca entram.
- **B. Marcadas `>` ou `<` sem destino confirmado**: `state ∈ {migrated, scheduled}` e `placement.status = pending`. (Decidiu migrar, mas ainda não escreveu no destino.)
- **C. Itens do Ano (Future Log) cujo período chegou**: entradas de tarefa/evento cujo `slot` (mês) já começou (ou com `dueDate` vencida) e que ainda estão abertas.

Excluir: concluídas, canceladas e as com `placement.status = placed`.

### 4.2 Interface

- **Painel lateral deslizando da direita para a esquerda.**
  - Mac: coluna de ~380 px **ao lado** da página (a página continua visível e editável à esquerda).
  - iPhone: folha quase em tela cheia vinda da direita; fecha com swipe para a direita ou botão.
- Abre por: (a) a faixa de montagem da semana/mês, (b) o fluxo "Fechar o dia", (c) um botão permanente discreto com contador. Setting para esconder o contador. Sem badge vermelho e sem tom de alarme.
- Itens agrupados por **log de origem**, mais antigos primeiro, com rótulo de origem e idade ("Wk 41 · Mon Oct 5 · 2 weeks ago").
- Cada linha usa os mesmos bullets, cores e gestos da página (seção 6).
- Tocar no texto da linha abre a página de origem com a entrada destacada. **No Mac, ela abre na segunda página** (seção 5, duas páginas abertas), ao lado da página em que se está escrevendo, e o painel permanece aberto. No iPhone, abre na página principal e a folha fecha.

### 4.3 Ações permitidas no painel (sempre uma entrada por vez)

- Tocar no bullet → concluída; tocar de novo → cancelada (riscada). Mesmo ciclo da página.
- Marcar `>` ou `<` (aviso "Migrated"/"Scheduled" com Undo; sem destino sugerido).
- Para itens da categoria B: botão **"I wrote it there"** → `placement.status = placed`. É uma confirmação **manual** do usuário.
- **Não existe**: selecionar vários, "limpar tudo", copiar texto, arrastar para uma página.

### 4.4 Reconhecimento de itens já reescritos (assistido, fase 4b)

O usuário disse que é desejável, mas provavelmente difícil. Solução que preserva a fricção:

- A V1 do painel usa só a confirmação manual (4.3).
- **Fase 4b (opcional, só depois da V1 estável):** ao terminar de digitar uma tarefa (blur/Enter), o app compara localmente o texto (normalizado: minúsculas, sem acentos, sem pontuação, sem stopwords) com as pendências das categorias A e B usando similaridade por tokens. Se houver correspondência forte, mostra um chip discreto e dispensável sob a linha: "Looks like the pending item '…' (Wk 41). Link it?". **Só com o toque do usuário** grava `placement.status = placed` e `placedEntryId`.
- Nunca vincular automaticamente. Sem IA e sem rede. Se gerar ruído, remover.

---

## 5. Momentos de uso (UX normativa)

Configuração de referência do Fernando: Weekly + Daily + Monthly + Future Log. Tudo abaixo respeita os princípios da seção 2.

**Faixa de montagem do período.** Faixa discreta e dispensável no topo, quando o log de um período ativo ainda não foi criado (ex.: "Week 43 isn't set up yet"). Tocar em **Set up week** cria a página **vazia** e abre o painel de pendências (seção 4). Dispensar esconde a faixa naquele período. O mesmo vale para o mês no início do mês. Não depende de push.

**Dia a dia.** O app abre na página do dia (log ativo mais fino) com o cursor numa linha nova. Criação preguiçosa: a página só é gravada na primeira escrita.

**Fechar o dia (opcional).** Ajuda a montar a lista do dia seguinte:
- Aparece como faixa dentro do app a partir de um horário configurável (padrão 20:00).
- Abre o painel de pendências **filtrado para as abertas de hoje** e deixa a página de amanhã ao lado (Mac) ou logo em seguida (iPhone), vazia, para o usuário escrever.
- **Desabilitável nos Ajustes** (padrão: ligado). Se desligado, a faixa nunca aparece.

**Virada do mês.** Mesmo painel, como consulta, junto com a página do novo mês, que já aparece com título e dias renderizados (seção 3.6). As marcações individuais continuam permitidas (seção 4.3).

**A qualquer hora.** Busca global (⌘K) e Index. Menu "…" da página com Export / Copy As / Share (seção 7).

**Duas páginas abertas (pedido do Fernando, Mac).** Um botão entre o de Open items e o "…" abre uma segunda página do caderno à direita, como o caderno aberto em duas páginas. As duas são editáveis e navegam de forma independente (a segunda guarda a última página aberta). As faixas (montagem, Fechar o dia, exportação) só aparecem na página principal. Em telas estreitas (iPhone) o botão não aparece.

**Caderno aberto (pedido do Fernando, Mac e iPad deitado).** Um botão com um livro aberto, ao lado do de segunda página, abre o caderno em duas páginas. Ajustes › Two-page spread escolhe o modo: **Flowing text** (padrão) faz o texto da página escorrer para a coluna da direita, como revista (a coluna da esquerda vai até o fim da tela e depois o texto continua à direita; quando a da direita enche, o caderno **vira para as páginas 3–4** sozinho, e um paginador discreto embaixo, "‹ Pages 3–4 of 4 ›", deixa voltar; o cursor mudar de página também vira; em tela estreita é a página normal, rolando; no Ano, jan–jun à esquerda e jul–dez à direita; no Month nada muda; vale também em Collections). **Next page** mostra à direita o **período seguinte no mesmo nível** (dia 19 | dia 20, Wk 43 | Wk 44, Oct | Nov, 2026 | 2027), como o Month com calendário e Month tasks. No modo Next page, ‹ › avançam de duas em duas páginas; a página da direita é editável, não tem cabeçalho próprio e, ao tocar no conteúdo dela (dia, Wk, mês), navega a página principal. Caderno aberto e segunda página são exclusivos: ligar um desliga o outro. Fica ligado até ser desligado (guardado no aparelho). Em páginas que não são de tempo (Index, Collections), não mostra nada à direita. Com qualquer página ao lado, o Month mostra calendário e Month tasks em uma coluna.

**Modo Pen (pedido do Fernando, iPad).** Uma cápsula ao lado do título, teclado | caneta, troca entre **Type** e **Pen** nas páginas livres (Day, Week, Collections). Só aparece num tablet (tela de toque ≥ 700 px); o Mac sempre abre em Type. Visual aprovado: `mockups/pen-mode.html`.
- **Pen** é a página com pauta discreta (1 px na cor das divisórias, a cada 40 px). Cada linha da pauta é uma entrada: escrever numa linha soma traços àquela entrada; escrever abaixo da última cria uma nova, e as linhas puladas viram linhas vazias, como no papel. As entradas digitadas aparecem na mesma pauta. Só a caneta (ou o mouse) deixa tinta; o dedo rola a página (rejeição da palma).
- Barra flutuante: Write, Draw (desenho, nunca convertido), Eraser (apaga o traço inteiro), Lasso, espessuras Fine / Medium / Bold, cores (tinta e as três do app, que acompanham o tema) e Undo.
- **Laço (Lasso):** contornar traços os seleciona (caixa tracejada); arrastar a caixa move a seleção, e ao soltar os traços passam a pertencer à linha onde caíram (ou a uma linha nova), com a transcrição refeita; o × da caixa apaga. Mover e apagar têm Undo. Linhas esvaziadas ficam como linhas em branco, para a página não pular.
- **Desenho:** a ferramenta Draw esconde a pauta. No modo Type, tocar no desenho o seleciona; arrastar move (entre as linhas da página e para os lados) e o canto redimensiona; o tamanho e o deslocamento ficam guardados, e no modo Pen o desenho continua onde foi feito. Escrever ao lado de um desenho junta a escrita ao desenho. Para apagar no modo Type: o × do desenho selecionado (ou Backspace/Delete), e Backspace numa linha vazia que só tem desenho. **A escrita à mão nunca é apagada pelo modo Type** (pedido do Fernando: traço é custoso de refazer): apagar o texto de uma linha manuscrita, apagar uma seleção que passa por ela ou dar Backspace no começo dela mantém a linha e a tinta; só a borracha do modo Pen apaga traços. Apagar todo o texto de uma linha escrita à mão no modo Type impede que ela seja transcrita de novo sozinha, e a linha deixa de aparecer no modo Type (a partir da próxima vez que a página abre; a letra continua no modo Pen). Depois da primeira transcrição, o modo Type nunca mais mostra a letra daquela linha.
- Regras de linha: entradas digitadas nunca recebem tinta (escrever nelas ou logo abaixo cria uma entrada nova depois delas); a linha logo abaixo de uma escrita à mão continua o mesmo parágrafo (também quando ali há uma linha em branco, que o parágrafo absorve), a não ser que comece com ponto, traço ou bolinha (novo item) ou bem mais à direita; letras com perna (g, p, q, j) não puxam a linha de baixo.
- A tinta é guardada **na própria entrada**, como traços vetoriais (`Entry.ink`), e sincroniza como o resto. No modo Type ela aparece dentro da linha (letra um pouco menor; desenho numa caixinha), até existir a transcrição.
- **Transcrição (etapa 2, teste na nuvem com a MyScript, escolha do Fernando):** a letra vira texto após uma pausa curta na escrita, ao trocar para Type e quando a conexão volta; a tinta é sempre salva antes, e offline a transcrição espera. O texto vai para a mesma entrada; no modo Pen a linha continua mostrando a letra, no modo Type mostra o texto. O bullet desenhado (ponto = tarefa, bolinha = evento, traço = nota) e o recuo (≈ 1 cm por nível) são lidos por geometria na primeira transcrição. O bullet desenhado ganha a cor do tipo, responde a toque e segurar como o digitado, e mostra ×, > e < por cima. Uma correção digitada no modo Type nunca é sobrescrita por uma nova transcrição. Mesmo corrigida, a linha escrita à mão continua mostrando só a letra no modo Pen (a correção aparece no modo Type e no texto exportado). Ajustes › Handwriting: idioma (Portuguese (Brazil) / English (US)) e as chaves da MyScript, guardadas só no aparelho.
- **Etapas:** (1) modo Pen sem conversão (feito); (2) transcrição da letra para texto em pt-BR/EN, primeiro testando na nuvem e depois no aparelho (ML Kit Digital Ink numa casca nativa), com o bullet desenhado reconhecido e colorido pelo tipo e o recuo da caneta virando indentação; a tinta continua sendo o original e o texto a transcrição; (3) PDF com a letra: feito (ver seção 7). Laço: feito.

### 5.1 Navegação entre Ano ↔ Mês ↔ Semana ↔ Dia

**Objetivo (pedido do Fernando):** trocar de nível em **1 toque**, sem menu e sem perder o contexto, tanto para descer (Ano → Mês → Semana/Dia) quanto para subir (Dia → Semana/Mês/Ano). O app mantém uma **data âncora** (o dia que o usuário está olhando); mudar de nível leva ao período que **contém a âncora**.

**Cabeçalho único em todas as páginas de tempo:**
- **Trilha (breadcrumb)** com os níveis ativos, ex.: `2026 › Oct › Wk 43 › 18`. **Cada item é tocável** e leva àquele nível; o nível atual fica em destaque. Níveis desativados nos Ajustes **não aparecem** (sem Weekly: `2026 › Oct › 18`).
- ‹ › = período anterior/próximo **no mesmo nível**.
- Botão de calendário (seletor de data: pula para qualquer dia, semana, mês ou ano) e botão **Today** (volta ao período de hoje no nível atual; segurar leva ao log ativo mais fino de hoje).
- Menu "…" (seção 7) e botão de Index à esquerda.
- iPhone: a trilha rola na horizontal se não couber; o item atual fica sempre visível.

**Descer tocando no próprio conteúdo**
- Ano → Mês: tocar no **cabeçalho do mês**.
- Mês → Dia: tocar no **número do dia**. Mês → Semana: tocar no rótulo **"Wk N"** da divisória.
- Semana → Dia: pela **trilha** (o item do dia mostra o dia âncora: hoje, se estiver na semana, ou o primeiro dia) e depois ‹ › na página do Dia. *A faixa de 7 dias foi retirada pelo Fernando (dava cara de app de notas digital); o código fica comentado em `src/pages/WeekStrip.tsx` caso volte.*
- Se o nível de destino estiver desativado, vai para o próximo ativo (Mês → Dia quando Weekly está desligado).

**Subir e andar de lado**
- Pela trilha: Dia → Semana, Dia → Mês ou Dia → Ano em 1 toque.
- Na página do **Dia**, ‹ › andam um dia por vez e o seletor de data pula para qualquer dia.
- Ao subir, a página **rola até o item de origem e o destaca brevemente** (ex.: voltar do dia 18 ao Monthly rola até a linha do 18).

**Voltar**
- O botão/gesto de voltar usa o **histórico real**: de Dia volta ao Mês se foi de lá que veio, restaurando rolagem e foco. Use rotas por URL (`/ano/2026`, `/mes/2026-10`, `/semana/2026-W43`, `/dia/2026-10-18`) com restauração de rolagem; isso também permite deep links.

**Transição visual:** descer = a linha ou célula tocada "expande" até virar a página (150–200 ms); subir = o inverso. Respeitar `prefers-reduced-motion` (fade curto ou nada).

**Regras**
- Navegar **nunca cria páginas nem grava nada**. Chegar a uma semana ou dia que não existe mostra a página vazia pronta para escrever (criação preguiçosa, princípio 7); a faixa de montagem (seção 5) continua valendo.
- **Sem swipe lateral para trocar de página.** No iPhone o swipe horizontal é reservado às marcações `>` e `<` das entradas; no Mac ele pode disparar o voltar/avançar do Safari (seção 6). Troca de período = ‹ ›, faixa de 7 dias, trilha e seletor de data.
- Atalhos de teclado no Mac para subir/descer de nível e ir a Hoje: definir na Fase 5, usando `event.code` e evitando atalhos reservados do Safari/macOS.

---

## 6. Gestos e interações

| Ação | iPhone | Mac |
|---|---|---|
| Concluir tarefa ou evento | 1 toque no bullet | clique no bullet · ⌘↵ |
| Cancelar (riscar) | 2º toque num bullet **já concluído** | clique de novo · ⌘↵ de novo |
| Voltar a aberta | 3º toque no riscado | clique de novo |
| Marcar `>` (migrar) | swipe **→** (esquerda para direita) | menu / ⌃⌥→ |
| Marcar `<` (agendar) | swipe **←** (direita para esquerda) | menu / ⌃⌥← |
| Menu do bullet | pressionar e segurar o bullet | clique direito, Ctrl+clique ou clicar e segurar |
| Prioridade `*` | menu do bullet · prefixo `*` | atalho (a definir) · menu · prefixo `*` |
| Indentar / desindentar | espaço / Backspace no início da linha | Tab / ⇧Tab |
| Colapsar / expandir | tocar no chevron | clicar no chevron |

- **Eventos** usam o mesmo ciclo de toque e os mesmos swipes/menu das tarefas (`×`, riscado, `>`, `<`). Se o ajuste "Estados em eventos" estiver desligado, o toque e o swipe no bullet do evento não fazem nada.
- **Notas** nunca têm estado: toque e swipe no bullet da nota não fazem nada. O tipo muda pelo menu.
- **Ciclo de toque**: aberta → concluída → riscada → aberta.
- **Direção dos swipes (confirmada pelo Fernando):** `>` no swipe para a direita e `<` no swipe para a esquerda; ajuste "Inverter direção dos swipes" para quem preferir o contrário. No Mac, ⌥→/⌥← ficam com o sistema (andar por palavra); os atalhos são ⌃⌥→/⌃⌥←.
- Ao revelar o swipe, mostrar o glifo (`>` ou `<`) e a ação ("Migrate"/"Schedule"); ao soltar, aviso com Undo.
- Menu do bullet (submenu): Tipo (tarefa/evento/nota), Estado, Prioridade, Inspiração, Explorar, Indentar/Desindentar, Copiar como…, Apagar (com desfazer).

**Riscos técnicos conhecidos (tratar na Fase 0/1):**
- No **iOS Safari não há evento `contextmenu` em long-press**. Implemente o long-press com Pointer Events + temporizador (~500 ms) e `-webkit-touch-callout: none` / `user-select: none` **apenas no bullet** (nunca no texto, para não quebrar a seleção).
- No **Mac/Safari, o swipe horizontal de dois dedos no trackpad pode disparar voltar/avançar do navegador**, e `overscroll-behavior-x` não resolveu isso nas fontes que consultei. Portanto: no Mac, **não depender de swipe**; use menu, atalhos e clique. Teste na Fase 0 se o PWA instalado no Dock sofre do mesmo problema.
- Use `event.code` (e não `event.key`) nos atalhos para funcionar em teclado AZERTY e QWERTY. Evite conflitos com atalhos do Safari/macOS.

---

## 7. Exportar, copiar e compartilhar

**Menu "…" no topo de cada página**, estilo editor de notas: **Export**, **Copy As**, **Share**. Dentro de cada um, três formatos: **Markdown**, **Rich Text**, **Plain Text**. (O Fernando só precisa de Markdown agora; construir os 3 desde o início para a versão comercial.)

- **Copy As** → clipboard. Rich Text via `ClipboardItem` com `text/html` + `text/plain` (Safari ≥ 13.1 documenta suporte; relatos antigos dizem que algumas versões do iOS copiavam só texto, então **validar no iPhone**). Fallback: evento `copy` com `DataTransfer`.
- **Export** → baixa arquivo (`.md`, `.html`, `.txt`).
- **Share** → `navigator.share()` (Web Share API: abre o menu padrão do iOS/macOS). **Exige gesto do usuário.** Esconder se `navigator.share` não existir. *(Atenção: o que o iOS não suporta é o Web Share **Target**, receber compartilhamentos; compartilhar para fora funciona.)*
- **Se houver seleção**, tudo acima exporta **só a seleção**.
  - A seleção é mapeada do DOM para as **entradas do modelo** e exportada a partir do modelo, **incluindo filhos colapsados**.
  - Guardar a seleção no estado do app a cada `selectionchange`, porque tocar em "…" no iOS pode desfazer a seleção nativa.
  - Interceptar o evento `copy` para que ⌘C e o "Copiar" nativo do iOS também levem itens colapsados.
- **Colapso nunca altera o que é exportado.**
- Mapeamento Markdown padrão (documentar em `docs/export-format.md` e manter estável): título da página como `# …`; tarefa `- [ ]`; concluída `- [x]`; migrada `- [>]`; agendada `- [<]`; cancelada `- ~~texto~~`; evento aberto `- ○ texto`; evento com estado usa o mesmo marcador das tarefas antes do glifo (ex.: `- [x] ○ texto`, `- [>] ○ texto`, `- ~~○ texto~~`); nota `- texto`; indentação de 2 espaços por nível; signifiers como prefixo textual.
- **PDF para imprimir (pedido do Fernando):** A5, folha lisa, desenhado em vetor a partir das entradas: a letra à mão onde foi escrita (como no modo Pen), desenhos, e as entradas digitadas com bullets coloridos (paleta em uso, versão clara) e o sinal de concluída dos Ajustes. Cada página do caderno começa numa folha nova; o Month mostra todos os dias numa folha, com as divisórias de semana; o Year, os 12 meses. Onde: "Export PDF" no menu "…" da página, e Ajustes › Print para um período (This month, This year, Everything), em ordem de caderno (Year, depois cada Month com suas semanas e dias; Collections no fim, em Everything).
- Ajuste opcional: "Estilo de glifos no Markdown": checkboxes (padrão) ou notação de pontos (`.`, `x`, `>`, `<`, `o`, `-`).

---

## 8. Visual

Objetivo: sensação de app de notas limpo para Apple, **sem copiar o Bear**.

- **Fonte:** `"Avenir Next"` como fonte do sistema (Fernando escolheu), com fallback `"Nunito Sans"` (open source, self-hosted) e depois `system-ui`. **Não redistribua Avenir Next**; verifique na Fase 0 se renderiza no PWA instalado do iPhone e do Mac. Para a versão comercial, o fallback open source passa a ser a fonte principal.
- Tipografia generosa: `line-height` ≈ 1.6; corpo 16–17 px; largura de leitura ~720 px centrada; margens amplas; pouco chrome; sem bordas pesadas.
- **Bullets coloridos (MUITO importante para o Fernando):**
  - A cor vem do **tipo do item raiz** (tarefa, evento, nota); **filhos herdam a cor do pai**, mas mantêm o glifo do próprio tipo.
  - `×`, `>`, `<` mantêm a cor do item; o texto concluído/cancelado fica atenuado.
  - Valores iniciais (refinar visualmente com o Fernando): tarefa `#E0533D`, evento `#3B82C4`, nota `#2A9D8F`.
- Tokens em variáveis CSS; 3 temas com **nomes próprios** (sugestão: "Paper" claro, "Graphite" escuro, "Night" OLED). Respeitar `prefers-color-scheme` + escolha manual. **Não usar** nomes de temas do Bear (ex.: Red Graphite).
- Nome, ícone, paleta e ilustrações próprios. Nada de assets do Bear.
- **Monthly e Ano:** layouts da seção 3.6. No tema escuro (referência do Fernando: fundo neutro quase preto), rótulo do mês em versalete pequeno, título grande, algarismos tabulares e divisórias de 1 px em baixo contraste. Cabeçalho de navegação da seção 5.1.
- **Idioma:** toda a UI em inglês (cabeçalho do documento). Glossário na seção 8.1.
- **Ícone do app:** arquivos prontos em `assets/icon/` (SVG mestre + PNGs). Use no manifest (`icons`, incluindo a versão *maskable*), no `apple-touch-icon` (iOS) e no favicon. Detalhes em `assets/icon/README.md`.
- **Escrever tem que ser prazeroso** (pedido do Fernando, subjetivo mas inegociável): a sensação de digitar deve ser tão boa quanto num editor de notas caprichado. Isso guia todas as decisões do editor: zero atraso ao digitar, nada pulando de lugar, transições suaves, tipografia generosa, foco no texto.
  - **O cursor piscante tem a cor do bullet da linha** (`caret-color` = cor do tipo do item, herdada do pai como os bullets; texto livre e títulos usam a cor de texto padrão).
- Painel lateral: sombra suave, animação de 150–200 ms (respeitar `prefers-reduced-motion`).
- **Animação de concluir (Ajustes › Done animation, escolha do Fernando):** Ink (padrão), Pop, Ripple, Sparks, Highlighter, Settle, Colored sparks; todas 40% mais lentas que o mockup; ao cancelar, uma versão mais quieta de cada. Funcionam com × e com ✓ (o ✓ é desenhado como traço; o × entra como carimbo, porque meio × parece `>`). Respeitam `prefers-reduced-motion`.
- Acessibilidade: alvos de toque ≥ 44 px (a área clicável do bullet é maior que o glifo), rótulos de estado para VoiceOver, contraste AA.
- Use a skill **frontend-design** ao construir a UI.

### 8.1 Glossário da UI (inglês)

Textos finais da UI. Onde o documento cita um termo em português, use o equivalente abaixo. O que não estiver na lista, escreva em inglês simples e curto, no mesmo tom (calmo, sem alarme, sem emoji).

| Referência no documento | Texto na UI |
|---|---|
| Ano / Future Log | Year |
| Mês / Monthly | Month |
| Semana / Weekly | Week (rótulo curto: "Wk 43") |
| Dia / Daily | Day |
| Índice / Index | Index |
| Coleções / Collections | Collections |
| Hoje | Today |
| Este mês | This Month |
| Tarefas do mês | Month tasks |
| Montar semana / mês | Set up week / Set up month |
| Pendências (painel e botão) | Open items |
| Já escrevi no destino | I wrote it there |
| Fechar o dia | Close the day |
| Estados em eventos (ajuste) | Event states |
| Inverter direção dos swipes (ajuste) | Reverse swipe directions |
| Primeiro dia da semana (ajuste) | First day of week |
| Faixa de 7 dias (ajuste) | Week strip |
| Estilo de glifos no Markdown (ajuste) | Markdown glyph style (opções: Checkboxes / Dot notation) |
| Tarefa / Evento / Nota | Task / Event / Note |
| Prioridade / Inspiração / Explorar | Priority / Inspiration / Explore |
| Concluir / Cancelar / Migrar / Agendar | Complete / Cancel / Migrate / Schedule |
| Exportar / Copiar como / Compartilhar | Export / Copy As / Share |
| Temas | Paper / Graphite / Night |

Datas e horas: `Intl.DateTimeFormat` com locale `en` (ex.: "Mon, Oct 5"); horário de 24 h por padrão, ajustável. Primeiro dia da semana padrão: segunda-feira. O texto que o usuário escreve é livre, em qualquer idioma; não force correção ortográfica em inglês (deixe o `lang` do campo seguir o sistema).

---

## 9. Modelo de dados

```ts
type EntryType = 'task' | 'event' | 'note' | 'text' | 'heading';
type EntryState = 'open' | 'done' | 'cancelled' | 'migrated' | 'scheduled'; // 'task' usa sempre; 'event' usa se o ajuste "Estados em eventos" estiver ligado; 'note' nunca

interface Entry {
  id: string;                 // ULID/UUIDv7
  logId: string;
  parentId: string | null;
  order: string;              // fractional index
  type: EntryType;
  state: EntryState;
  text: string;               // texto simples + markdown inline mínimo
  signifiers: Array<'priority' | 'inspiration' | 'explore'>;
  collapsed: boolean;
  dueDate?: string;           // ISO; data-alvo opcional (agendamento)
  slot?: string;              // linha fixa do layout onde a entrada vive: 'AAAA-MM-DD' no Monthly; 'AAAA-MM' no Ano (Future Log)
  placement?: {               // só para migrated/scheduled
    status: 'pending' | 'placed';
    placedEntryId?: string;   // preenchido só se o usuário confirmar vínculo (4.4)
    confirmedAt?: string;
  };
  createdAt: string;
  updatedAt: string;
}

type LogKind = 'future' | 'monthly' | 'weekly' | 'daily' | 'collection';

interface Log {
  id: string;
  kind: LogKind;
  title: string;
  periodStart?: string;       // ISO date
  periodEnd?: string;
  createdAt: string;
  updatedAt: string;
}

interface Settings { /* seção 12 */ }
```

- Pendências (seção 4.1) e Index são **consultas derivadas**; não armazenar.
- Título do mês, linhas dos dias, cabeçalhos dos 12 meses, trilha de navegação e a faixa de 7 dias são **layout derivado da data**, não `Entry`. O Ano é um `Log` de `kind = 'future'` com `periodStart` em 1º de janeiro.
- Migrar **não** cria entrada nova: só altera `state` e `placement` da origem. O destino é escrito pelo usuário como entrada comum.

---

## 10. Stack e arquitetura

- **Vite + React + TypeScript**, `vite-plugin-pwa` (service worker + manifest, ícones e meta tags de iOS).
- **Dexie** (IndexedDB) com `dexie-react-hooks` (`useLiveQuery`); **todo acesso a dados passa por uma camada `repository`** (`src/data/`). A UI nunca chama o Dexie diretamente. Assim o backend de sync pode ser trocado sem reescrever o app.
- **Editor:** decisão a tomar no início da Fase 1 com um protótipo curto, comparando **(a)** TipTap/ProseMirror com lista aninhada e `id` por nó (sincronizar por diff de entradas) e **(b)** editor próprio linha a linha. Critérios: seleção multilinha nativa, colapso, bom comportamento no teclado do iOS, mapeamento 1:1 com `Entry`, exportação de seleção. Registrar a decisão em `docs/decisions.md`.
- Estilos: CSS variables (+ Tailwind, se ajudar).
- Hospedagem estática gratuita (Cloudflare Pages ou Vercel). HTTPS é obrigatório para PWA/Service Worker.
- Instalação: iPhone, Safari → Compartilhar → Adicionar à Tela de Início. Mac, Safari → Adicionar ao Dock (ou Chrome/Edge → instalar). Confirmar o passo a passo exato no Mac na Fase 0.
- **Instalar antes de usar:** segundo um teste antigo, o IndexedDB do Safari e o do app instalado são isolados no iOS. Então os dados reais só entram **depois** de instalar.

---

## 11. Sync e custos

**Decisão atual: Dexie Cloud, plano gratuito** (custo zero agora, caminho de escala depois).

- Por quê: foi feito para apps offline-first (o app funciona 100% offline e o sync é complemento). O plano grátis lista todos os recursos, incluindo autenticação.
- **Supabase foi descartado por ora**: projetos no plano grátis pausam após 7 dias sem atividade e precisam ser reativados manualmente; e o offline ficaria por nossa conta.
- **Alternativa se o Dexie Cloud não servir:** Instant (plano grátis sem pausa de projetos e com 1 GB) ou Jazz. Por isso a camada `repository`.

**Itens NÃO verificados — confirmar na Fase 0 e registrar em `docs/spike-results.md`:**
1. Preço por usuário do plano pago do Dexie Cloud (relevante para a versão comercial).
2. Limite de armazenamento do plano grátis (a página de preços tem números divergentes entre versões).
3. Se o usuário do plano grátis ("evaluation user") expira ou tem restrições além dos limites de taxa.
4. Comportamento de conflito ao editar offline nos dois aparelhos.

---

## 12. Ajustes (Settings)

- Logs ativos: Monthly / Weekly / Daily (mínimo 1; Index e Future Log fixos).
- **Estados em eventos** (concluir, cancelar, migrar, agendar): ligado/desligado (**padrão: ligado**). Desligado: eventos sem estado e fora das pendências. Eventos que já têm estado gravado o mantêm visível; não apagar dados ao desligar.
- Primeiro dia da semana (padrão: segunda); formato de data (padrão: DD/MM).
- Faixa de montagem do período: ligar/desligar.
- **Fechar o dia:** ligar/desligar (padrão: ligado) e horário (padrão: 20:00).
- Contador do botão de pendências: mostrar/esconder.
- Inverter direção dos swipes.
- ~~Faixa de 7 dias nas páginas de Semana e Dia~~ (retirada; ver seção 5.1).
- Prefixos de rapid logging (configuráveis).
- Estilo de glifos no Markdown.
- Tema: Papel / Grafite / Noite / automático. Fonte: Avenir Next (padrão) ou fallback.
- **Paleta** (pedido do Fernando): cores dos bullets de tarefa, evento e nota. Classic (padrão, as cores da seção 8; tarefa vermelha), Ocean (tarefa azul), Forest (tarefa verde), Dusk (tarefa violeta) e Ink (tarefa cor de tinta, o resto em tons quietos); cada uma lidera com uma cor diferente e tem versão clara e escura, e o tema escolhe qual usar. A cor de destaque acompanha a tarefa. O Rich Text exportado usa a paleta em uso (versão clara). Guardada no aparelho, como o tema.
- Exportar tudo (JSON + Markdown) e importar JSON.

---

## 13. Fases e critérios de aceite

**Fase 0 — Spike de risco (primeira tarefa; descartável).**
Um "hello PWA" implantado em HTTPS e instalado no iPhone e no Mac. Validar e registrar em `docs/spike-results.md`:
- instalação; abertura em modo standalone; funcionamento offline;
- persistência do IndexedDB após vários dias; `navigator.storage.persist()`;
- Dexie Cloud entre os dois aparelhos (+ itens da seção 11);
- `navigator.share`, cópia rich text (HTML) e **seleção preservada ao tocar em "…"** no iPhone;
- long-press no bullet (Pointer Events) e menu de clique direito no Mac;
- se o swipe horizontal no Mac instalado dispara navegação do navegador;
- botão/gesto de voltar (borda no iPhone, swipe no Mac) funcionando com o histórico de rotas do PWA instalado (seção 5.1);
- Avenir Next renderizando no PWA instalado.
*Aceite:* documento com resultado de cada item e a recomendação (seguir / ajustar plano). Parar e avisar o Fernando se algo crítico falhar.

**Fase 1 — Núcleo local.**
Editor com rapid logging, estados, ciclo de toque, signifiers, subitens com colapso, páginas Daily e Weekly, **Monthly e Ano com layout fixo (seção 3.6)**, **navegação entre Ano/Mês/Semana/Dia (seção 5.1)**, Collections e Index básico, ajuste de logs ativos, bullets coloridos e tema base (Avenir Next).
*Aceite:* digitar `. tarefa` cria tarefa colorida; indentar cria pai com chevron; colapsar/expandir funciona; 1 toque conclui e 2º toque risca (tarefas e, com o ajuste ligado, eventos; notas nunca); desligar "Estados em eventos" faz o toque no evento não ter efeito; não é possível ficar sem pelo menos 1 log de tempo ativo; nada é criado ou movido automaticamente; funciona offline.
*Aceite (Monthly e Ano):* o Monthly mostra rótulo e título do mês e todos os dias (número + inicial) com divisórias de semana, **sem gravar nada** até o usuário escrever; uma frase longa reduz a fonte até 85% e depois quebra linha, sem truncar; o Ano mostra os 12 meses com o nome já escrito e cada área cresce com o conteúdo.
*Aceite (navegação):* da trilha vai-se de Dia a Semana, Mês ou Ano em 1 toque; do Ano ao Mês e do Mês ao Dia ou à Semana tocando no conteúdo; voltar restaura a rolagem; navegar para uma página inexistente **não a cria**; com Weekly desligado a trilha omite a semana.

**Fase 2 — Sync e PWA.**
Dexie Cloud (ou alternativa conforme o spike), login, indicador discreto de estado de sync, ícones/manifest finais (usar os arquivos de `assets/icon/`).
*Aceite:* escrever no iPhone offline e ver no Mac depois de reconectar, e vice-versa; sem perda de dados em edição simultânea simples.

**Fase 3 — Export, Copy As e Share.**
Menu "…", 3 formatos, seleção (com colapsados), `copy` interceptado, Share onde houver suporte.
*Aceite:* copiar uma página em Markdown em ≤ 3 toques; selecionar linhas com itens colapsados e copiar leva os filhos; colar em app nativo funciona; Export baixa o arquivo.

**Fase 4 — Painel de pendências e rituais.**
Painel lateral, categorias A/B/C, gestos de swipe/long-press/menu, faixa de montagem de semana/mês, Fechar o dia (desabilitável), "Já escrevi no destino".
*Aceite:* uma tarefa `•` de semana anterior aparece; uma `>` sem destino aparece; ao confirmar o destino sai do painel; **nenhuma ação em massa existe**; o painel nunca altera entradas sem gesto individual; desligar "Fechar o dia" remove a faixa.
**Fase 4b (opcional):** reconhecimento por similaridade (seção 4.4).

**Fase 5 — Index, busca e acabamento.**
Index completo, busca global (⌘K), coleções fixadas, três temas, atalhos de teclado do Mac, acessibilidade, importar/exportar tudo.

---

## 14. Roadmap (fora do escopo do PWA)

Quando houver código nativo (iOS/macOS):
- **Push notifications confiáveis** (lembretes de planejamento e de Fechar o dia). No PWA, ficam só as faixas dentro do app. *As fontes que consultei divergem sobre push em PWA na UE.*
- **Receber compartilhamentos de outros apps** (Web Share *Target* não é suportado no iOS).
- Atalhos do sistema, widgets e Spotlight.
- **Barra própria acima do teclado no iPhone** (indentar, desindentar, prioridade). No PWA não dá: o iOS sempre mostra a barra de formulário (^ v ✓) e uma barra nossa fica brigando com ela (testado na Fase 1 e abandonado). No app nativo, substituir a barra do sistema (`inputAccessoryView`).
- **Fotos por mês no Ano:** poucas fotos para cada mês (galeria pequena em cada seção do Ano). Exige armazenar e sincronizar blobs; o Dexie Cloud separa os limites de armazenamento de blobs e de objetos (verificar os valores). Não implementar no PWA agora; só não bloquear essa evolução no modelo de dados.
- **Versão comercial:** contas, planos, backend de sync definitivo (revisar custos), site e identidade visual próprios, mais a **liberação de nome e marca**:
  - Busca de anterioridade de "Bullet Life" (INPI, EUIPO, USPTO) e consulta a advogado de marcas. O nome não foi verificado nesses registros.
  - Existe o app "Bullet: Journal, Daily Planner" (Hamish Johnson) no mesmo nicho; risco de confusão com "Bullet".
  - A Lightcage, LLC é dona de **BULLET JOURNAL** e **BUJO** e declara que o uso comercial do nome e do *sistema* exige permissão por escrito. Avaliar licença ou consulta antes de lançar. Nunca usar essas marcas na UI, na loja ou no marketing.
- Possível reconhecimento mais sofisticado de itens reescritos, se a fase 4b mostrar valor.

---

## 15. Premissas assumidas (confirmar com o Fernando)

1. Direção dos swipes: `>` = para a direita, `<` = para a esquerda (com opção de inverter). **Confirmado pelo Fernando.**
2. Terceiro toque volta o item riscado para aberto.
3. Cores iniciais dos bullets e nomes dos temas (seção 8).
4. Prefixos: `.` tarefa, `o. ` evento, `- ` nota.
5. Primeiro dia da semana: segunda; Fechar o dia ligado às 20:00.
6. Eventos ciclam estado como tarefas (com ajuste para desligar); notas nunca ciclam.
7. Prioridade: menu do bullet + prefixo `*` (o Fernando não sabe qual seria mais intuitivo; reavaliar após uso real). Sem barra própria acima do teclado no PWA (ver seção 14).
8. **Ano = uma página por ano civil (jan–dez)**, e não "12 meses móveis a partir de hoje". O Fernando chamou de "yearly log" e descreveu uma linha por mês.
9. Monthly: texto livre por dia (método purista); a fonte encolhe até 85% e depois a linha quebra e cresce.
10. Navegação: trilha tocável + faixa de 7 dias + botão Hoje, sem swipe lateral (seção 5.1).
11. Nome **Bullet Life**, com as ressalvas de marca da seção 14.
12. Ícone oficial (v2, escolhido pelo Fernando): bola vermelha grande no centro, circulada por um anel azul vazado, com uma barra verde reta logo abaixo, como um subscrito; fundo off-white. (O v1, duas bolas numa rampa, está no histórico do git.) Arquivos em `assets/icon/` (ver README); pode ser trocado sem impacto no código.

---

## 16. Regras de trabalho para o Claude Code

- Comece pela Fase 0 e só avance com os critérios de aceite cumpridos.
- Se algo neste documento parecer conflitar com os princípios da seção 2, **os princípios vencem**; pergunte ao Fernando.
- Não invente funcionalidades que "ajudam" fazendo por ele. Na dúvida, mostre a informação e deixe a ação com o usuário.
- Mantenha `docs/decisions.md` (decisões técnicas), `docs/spike-results.md` e `docs/export-format.md` atualizados.
- Commits pequenos e em inglês; testes para: derivação de pendências, ciclo de estados, exportação (incluindo colapsados e seleção) e regra de logs ativos.

---

## 17. App nativo (iPad e iPhone; branch `claude/native-app`)

**Por quê (Fernando, 29/10/2026):** o PWA ficou estável, mas a caneta tem um limite que uma página web não contorna: às vezes o iPadOS não entrega o toque da caneta ao Safari (o diagnóstico mostrou tentativas sem nenhum evento na página; não é o Scribble). No app nativo a escrita usa **PencilKit**, que recebe cada toque da caneta direto do sistema. O PWA continua no ar durante a transição.

**Decisões (Fernando):**
- **Plataformas:** iPad + iPhone primeiro, um app SwiftUI. Mac depois, sem retrabalho: pelo **Mac Catalyst** (ou o app de iPad rodando em Macs Apple Silicon), que reaproveita o mesmo código. Toda a lógica fica num pacote sem dependência de tela (`BulletLifeCore`).
- **Sync: iCloud (CloudKit).** Grátis e nativo. Os modelos (SwiftData) já nascem no formato que o CloudKit exige (tudo com valor padrão, nada único, sem relações; entradas apontam para log e pai por id, como no PWA), então ligar o sync é configuração, não migração. **Exige a conta paga do Apple Developer Program** (US$ 99/ano); com a conta grátis o app instala por 7 dias e sem iCloud. O PWA (Dexie Cloud) e o app nativo **não** sincronizam entre si: os dados vêm uma vez, pelo backup JSON do PWA.
- **Reconhecimento de escrita: Google ML Kit Digital Ink, no aparelho** (offline, grátis, pt-BR e inglês; modelo de ~20 MB baixado uma vez). Entra na fase N3, como dependência própria (CocoaPods/SPM, o que o ML Kit oferecer na época).
- **Mesmos dados e mesmas regras do PWA:** o `BulletLifeCore` é um porte linha a linha do modelo (o JSON do PWA, incluindo a tinta), das datas, do rapid logging, do ciclo de estados, das chaves de ordem (`fractional-indexing`, com os mesmos vetores de teste) e das regras de linha da caneta. Os testes repetem os casos do PWA.

**Fases (cada uma termina testada no iPad do Fernando):**
- **N0 — Base (feito):** projeto (XcodeGen), `BulletLifeCore` com testes, armazenamento local (SwiftData), páginas Day e Week com linhas editáveis (rapid logging, bullets coloridos, toque no bullet cicla o estado, menu no bullet com tipo, migrar/agendar, prioridade, indentar, apagar), navegação ‹ Today ›, Ajustes (importar o backup do PWA, primeiro dia da semana, estados em eventos, sinal de concluída).
- **N1 — Editor de verdade:** um editor de página inteira em TextKit (seleção entre linhas, Enter/Backspace/Tab como no PWA, colapso, listas numeradas, `due:`), no lugar de um campo por linha. *Em andamento:* as regras de teclado (Enter, Backspace no início da linha, apagar entre linhas, colar, Tab e espaço no início para indentar, listas numeradas, a escrita à mão nunca apagada pelo Type) estão no `BulletLifeCore`, testadas com os casos do PWA; o editor (`PageEditorView`, um UITextView com bullets e chevrons na margem, ⌘↩, prefixos também do Scribble, Undo próprio) substituiu os campos por linha. Linhas escritas à mão cujo texto foi apagado no Type somem do Type na próxima abertura da página (continuam no Pen); o Type não mostra marca de lápis. No modo Type, a tinta aparece na linha: a letra ainda não transcrita (a 70%, como escrita) e os desenhos sempre, numa caixa que se seleciona com um toque, redimensiona pelo canto, move para os lados e apaga com × (ou Backspace na linha vazia); a regra de quando e em que tamanho está no `BulletLifeCore` (`InkPreview`, testada). Arrastado, o desenho flutua sobre a página, solto das linhas (pedido do Fernando): fica onde foi solto, pode cobrir texto e pode ir abaixo da última linha (a página cresce para ele); a linha dele continua onde estava, e o texto não abre espaço para ele. Todos flutuam, também os que nunca foram arrastados (começam na altura da linha deles, sem espaço reservado). `due:` como no PWA (leitura, gravação como data, rótulo, ordenar a pedido no `BulletLifeCore`, com os testes do PWA): a data vira pílula colorida pela urgência, tocar nela abre um calendário, e listas de irmãos com datas fora de ordem mostram "Sort by date"; Ajustes › Date format (DD/MM ou MM/DD). Negrito, itálico e marca-texto como no PWA (`**`, `*`, `==` no texto; marcas escondidas, aparecem apagadas com o cursor dentro): ⌘B, ⌘I, ⌘⇧H e o menu Format do sistema (B / I), que escrevem as marcas. *Decisão do Fernando: no app nativo não há swipe para migrar/agendar; `>` e `<` ficam só no menu do bullet (e no menu do Open items).* Problema conhecido (Fernando: não crítico): Backspace no início de uma linha indentada às vezes tira o bullet em vez de desindentar.
- **N2 — Modo Pen com PencilKit:** pauta, tinta por entrada (o formato de traço do PWA, convertido de/para `PKStroke`), regras de linha do `BulletLifeCore`, borracha, laço, desenho, Undo. Rejeição de palma nativa. *Em andamento:* chave Type | Pen no cabeçalho (só no iPad), escrita e desenho com PencilKit (dedo rola, caneta escreve), cores, espessuras, borracha de traço inteiro e Undo próprio; as linhas digitadas aparecem na pauta. Laço com o `PKLassoTool` do sistema: arrastar a seleção leva os traços para a linha onde caíram (ou uma nova), com a transcrição refeita e linhas esvaziadas em branco (regra no `BulletLifeCore`, testada); apagar pelo menu do próprio laço; Undo nosso. O bullet desenhado (e o digitado) responde ao toque do dedo (o toque da caneta continua sendo escrita) e ao segurar (menu com tipo, migrar/agendar, signifiers); ×, > e < aparecem por cima do bullet desenhado, e linhas concluídas ou canceladas ficam atenuadas (canceladas, riscadas). A validar no iPad.
- **N3 — Transcrição no aparelho (ML Kit Digital Ink):** a mesma lógica do PWA (parágrafo numa linha só, bullet e recuo pela geometria, correção nunca sobrescrita). *Em andamento:* ML Kit pelo CocoaPods (`native/Podfile`), idioma em Ajustes › Handwriting (modelo baixado na primeira vez, depois offline), transcrição após 2,5 s sem escrever ou ao trocar para Type, com a mecânica do `BulletLifeCore` (testada). Falta testar no iPad e mostrar o texto transcrito no modo Type de forma caprichada (vem com a N1).
- **N4 — O resto do caderno (feito, a validar no iPad):** trilha `2026 › Oct › Wk 44 › 29` com os logs ativos, ‹ Today › (segurar Today vai ao log mais fino de hoje) e calendário em todas as páginas de tempo; Month (todos os dias, divisória de semana com "Wk N", frase que encolhe até 85% antes de quebrar, Month tasks) e Year (12 meses, nome fixo ao rolar); voltar pelo histórico (botão ‹ no canto) e, ao subir de nível, a página rola até o dia ou mês de origem e o destaca; Index (Year atual, coleções fixadas, Collections A–Z com alfinete, New collection, Today e calendário); Collections como páginas livres (Type e Pen) com nome editável; Open items (painel ao lado no iPad, folha no iPhone; tocar no texto abre a página e destaca a entrada); faixas "Set up week/month" e "Close the day" (abre amanhã e o painel com o que ficou aberto hoje); menu "…" com Export, Copy As e Share (Markdown, Rich Text, Plain Text; com seleção, só a seleção, com filhos colapsados) e Export PDF (A5, letra à mão onde foi escrita); ⌘C copia do modelo, com filhos colapsados; Ajustes: logs ativos (mínimo 1), faixa de montagem, Close the day e horário, estilo de glifos no Markdown, Print (This month, This year, Everything). A rolagem exata ao voltar ainda não é restaurada (só a rolagem até a origem). Colar linhas copiadas do app (ou Markdown e texto com bullets) recria as entradas com tipo, estado e recuo; números de lista em negrito na cor do bullet; signifiers na margem; apagar coleção pelo menu "…" da coleção, com dupla confirmação.
- **Adaptação nativa (pedido do Fernando):** o PWA é a especificação, não um molde: cada peça segue o jeito do iOS (inspector para o painel, menus e folhas do sistema, share sheet para exportar e imprimir). Controles flutuantes (barra da caneta, faixas) usam o **Liquid Glass** quando o sistema tem (iOS 26+, compilado com Xcode 26), com o material translúcido como alternativa.
- **Aparência (feito, a validar no iPad):** Ajustes › Look: tema (Automatic, Paper, Graphite, Night: a janela fica clara ou escura, e o Night usa o preto e os tons mais fundos), paleta (Classic, Ocean, Forest, Dusk, Ink, com versão clara e escura; o Rich Text e o PDF usam a clara) e Done animation (Ink, Pop, Ripple, Sparks, Highlighter, Settle, Colored sparks, em Core Animation, com versão mais quieta ao cancelar, desligadas pelo Reduce Motion), com uma tarefa de exemplo para tocar. As animações tocam no toque e no ⌘↩ do modo Type.
- **Duas páginas e caderno aberto (feito, a validar no iPad):** no iPad em tela larga, um menu de páginas na barra (One page, Two pages, Open book; o menu do sistema marca a escolha, e escolher uma desliga as outras; guardado no aparelho). Two pages (decisão do Fernando): a página da direita é só de consulta, sem controles, sem escrever e sem caneta; o texto se seleciona como num PDF, e só o bullet responde ao dedo (toque muda o estado; segurar abre o menu, sem indentar nem apagar), gravando só aquela entrada. O único controle é um × no canto superior direito, que leva ao Index; dali (ou de um toque no Open items) ela abre outra página. Ela lembra a última página (guardada no aparelho; na primeira vez, o Index) e se atualiza quando a da esquerda grava a mesma página. Os toques que navegam (dia, Wk, mês) ficam desligados nela. Open book: a direita é o período seguinte no mesmo nível, editável, só com o nome (sem controles), e ‹ › andam duas páginas. As faixas ficam só na página da esquerda. O Month sozinho numa tela larga mostra os dias e o Month tasks lado a lado (como no PWA); com outra página ao lado, uma coluna. Segurar a divisória entre as páginas mostra uma alça (como o Split View); arrastar para a direita fecha a página da direita, para a esquerda fecha a da esquerda, e a que fica vira One page (no Two pages, a esquerda vai para a página consultada; no Open book, para o período seguinte). Flowing text fica para depois.
- **Busca (feito, a validar no iPad):** lupa na barra e ⌘K abrem uma folha do sistema com o campo pronto; acha entradas de qualquer página (também dentro de colapsados) e nomes de coleções, sem diferenciar maiúsculas e acentos, todas as palavras, as mais recentes primeiro (`Search` no `BulletLifeCore`, com os testes do PWA); tocar abre a página com a entrada destacada. Ajustes: esconder o contador do Open items.
- **Roadmap — desfoque do cabeçalho (Fernando):** o desejo é o borrão gostoso de vidro, como na Central de Controle. Os materiais do SwiftUI trazem um véu claro embutido e não deixam regular a intensidade; as tentativas manuais (vidro tingido, desfoque parcial, desfoque progressivo em camadas) não chegaram lá e foram desfeitas. O caminho é o efeito de borda nativo do iPadOS 26 (os cabeçalhos reconhecidos pelo sistema como barra), testado primeiro numa página só, isolada, e com controles de ajuste ao vivo nos Ajustes, antes de levar ao app todo. Hoje: o vidro coberto pelo papel do tema (60% Paper, 88% Night, 95% Graphite).
- **N5 — iCloud:** CloudKit ligado (conta paga), indicador de sync, e a importação do PWA como passo único de migração.
