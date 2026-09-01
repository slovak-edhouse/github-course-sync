# Práce s přiděleným repozitářem

Ve školní organizaci GitHub máte jeden nebo více soukromých repozitářů.
Repozitář může být určen pro celý předmět, část výuky nebo jeden úkol. Učitel
vám vždy řekne, který repozitář máte použít. Jeho název určil učitel, takže
nemusí obsahovat vaše uživatelské jméno z GitHubu. Repozitář vlastní škola, vy
do něj můžete zapisovat a učitel k němu má správcovský přístup. Ostatní
studenti váš repozitář nevidí.

## První přihlášení

1. Přijměte pozvánku do školní organizace nebo k repozitáři.
2. Otevřete odkaz na repozitář, který vám dal učitel.
3. Naklonujte jej pomocí klienta Git, kterého používáte ve výuce.
4. Pracujte ve větvi `main`.

Nevytvářejte vlastní repozitář ani fork. Repozitář vytváří učitel a může do něj
doplňovat nové úkoly, opravy nebo podpůrné materiály.

## Před začátkem práce

Ve svém klientu Git:

1. načtěte informace o změnách ze vzdáleného repozitáře `origin` (`fetch`);
2. pokud jsou dostupné změny, stáhněte je z `origin/main` do místní větve
   `main` (`pull`).

Někteří klienti tyto operace spojují nebo provádějí `fetch` automaticky. Názvy
tlačítek se mohou lišit, základní operace Git jsou ale stejné.

Potom byste měli vidět nové nebo opravené materiály určené pro daný repozitář.
Jestli váš klient Git hlásí konflikt nebo očekávané materiály chybějí,
nepoužívejte vynucený přepis (`force push`) a neupravujte historii. Zavolejte
učitele.

## Během práce

- Pracujte pouze ve svém přiděleném repozitáři.
- Nevytvářejte předem složky ani soubory, které má učitel vyhrazené pro budoucí
  materiály.
- Ukládejte změny v menších smysluplných commitech.
- Do repozitáře nevkládejte hesla, tokeny, osobní údaje ani jiné tajné
  informace.

## Konec práce

1. Zkontrolujte změněné soubory.
2. Vytvořte commit s krátkým a výstižným popisem.
3. Odešlete místní větev `main` do vzdáleného repozitáře `origin` (`push`).
4. Na webu GitHubu ověřte, že je poslední commit v repozitáři vidět.

Commit, který zůstal pouze na školním počítači, není odevzdaný.

## Konflikt při přidání nového zadání

Když se vaše změny střetnou s novými materiály od učitele, zůstane v
repozitáři otevřený synchronizační pull request. Jednoduchý konflikt můžete po
domluvě s učitelem vyřešit přímo na GitHubu:

1. Otevřete pull request, jehož název začíná
   `GitHub Course Sync: Course materials update`.
2. Použijte `Resolve conflicts`.
3. S učitelem rozhodněte, která výsledná podoba souboru je správná, a odstraňte
   značky konfliktu.
4. Použijte `Mark as resolved` a `Commit merge`.
5. Nakonec použijte `Merge pull request`.

Vyřešení konfliktu a sloučení pull requestu dokončete společně. Pokud tlačítko
`Resolve conflicts` není dostupné nebo je konflikt složitý, nic nemažte, pull
request nezavírejte a zavolejte učitele.

## Co běžně nepotřebujete

Pro běžnou práci nepoužívejte:

- `Fork` ani `Sync fork`;
- vzdálený repozitář `upstream`;
- `force push`;
- změny oprávnění a nastavení repozitáře;
- mazání větví vytvořených učitelem pro synchronizaci.

Stačí tento běžný cyklus:

```text
Fetch/Pull → práce → Commit → Push
```
