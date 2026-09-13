"use client";

import { SideNav, ThemeSwitcher } from "@vaam-apps/ui";

import { MoreMenu } from "./more-menu";
import { SignedInBar } from "./signed-in-bar";
import { LayoutDashboard } from "lucide-react";
import { usePathname } from "next/navigation";

import { NAV_ENTRIES } from "../dash/resources";

/**
 * The signed-in chrome: the rail, the "More" drawer, who is signed in, and
 * the way out.
 *
 * # The rail is rendered from the resource registry, not from a second list
 *
 * `NAV_ENTRIES` is derived from `DASH_RESOURCES` — the same array Refine
 * routes on — so a resource with no page, or a page missing from the rail,
 * is a failing test rather than a dead link. That is Lane 4's whole point,
 * and it replaces `nav.tsx`'s hand-kept `NAV_LINKS`. `MoreMenu`'s own drawer
 * reads the same array rather than keeping a second copy.
 *
 * # `currentPath` comes from the caller
 *
 * `@vaam-apps/ui` has no dependency on Next, so `SideNav` takes the active
 * path rather than reading a router. `usePathname()` is that value here, and
 * `MoreMenu` gets the same string for its `aria-current` handling.
 *
 * # Sign-out stays a POST to the existing Server Action
 *
 * It is a footer item that submits a form, not a link. Issue #88 item 4: a
 * sign-out reachable by `GET` is the action an `<img src>` or a link scanner
 * fires, and `signed-in-bar.tsx` already made it a POST for that reason. The
 * action itself is unchanged and still revokes before it clears — in both
 * places it now renders, `<main>` and the drawer.
 */
export interface AppShellProps {
  readonly email: string;
  readonly merchantId: string;
  readonly signOut: () => Promise<void>;
  readonly children: React.ReactNode;
}

export function AppShell({
  email,
  merchantId,
  signOut,
  children,
}: AppShellProps) {
  const pathname = usePathname();
  const first = NAV_ENTRIES[0];

  return (
    <div className="flex min-h-screen">
      {/*
        The app's one <h1>, and it is `sr-only` on purpose.
        It lived in the root layout's <nav> and moved here with the rail,
        because that layout wraps `/login` too and a sign-in form should not
        carry a link to a page nobody signed in can open. It is NOT inside
        `accountSlot`: `SideNav` drops that slot below `lg`, which would take
        the document's only <h1> away on a narrow screen. The rail already
        shows the brand visually through `topItem`, so this carries the name
        for a screen reader without drawing it twice.

        Still an <h1>, with every screen's own title an <h2> under it — the
        hierarchy `dashboard.cy.ts` asserts in thirteen places.

        Wrapped in a bare `<header>` — a landmark (implicit `banner` role)
        because it is not nested in `<article>`/`<aside>`/`<main>`/`<nav>`/
        `<section>` — rather than left a direct child of this flex row: axe's
        `region` rule ("all page content should be contained by landmarks")
        does not exempt content that is visually hidden, only content outside
        the accessibility tree entirely, and `sr-only` keeps this in it. A
        bare `<div>` here is not a landmark and this h1 was the one thing on
        the signed-in shell sitting outside one — found by `a11y.test.tsx`'s
        case for this composition, which had no coverage at all until it was
        added.
      */}
      <header>
        <h1 className="sr-only">vpay dashboard</h1>
      </header>
      {/*
        The in-flow sidebar is full height and pinned to the top, and both
        halves of that need this wrapper because `SideNav` takes no
        `className`.

        **Measured before the change** (1440x900, real render): the sidebar
        carries `xl:h-full`, but its only ancestor is `flex min-h-screen` —
        a *min*-height, not a definite one — so `height: 100%` resolved to
        `auto` and the nav was **407px tall** with `position: static`. It
        ended partway down the viewport and scrolled away with the page.

        `xl:h-screen` gives the definite height `xl:h-full` needs, and
        `xl:sticky xl:top-0` pins it. The nav's own `xl:overflow-y-auto`
        then scrolls the nav's contents rather than the page when the list
        outgrows the viewport.

        `contents` below `xl` is deliberate: at those widths the rails are
        `position: fixed` and portalled to `document.body`, so a box here
        would be an empty column the rails never occupy. `display: contents`
        adds no box at all, which keeps every measurement in the comment on
        `<main>` below exactly as it was.
      */}
      <div className="contents xl:sticky xl:top-0 xl:block xl:h-screen">
        <SideNav
          /*
          A distinct icon from the group below. `topItem` and the one
          `Payments` entry both rendered `CreditCard` at first, so the rail
          showed the same glyph twice with nothing to tell them apart —
          visible in `03-payments.png` from the e2e run before this line
          existed. The top item is the console; the entry is the resource.
        */
          topItem={{
            label: "Console",
            href: first?.href ?? "/",
            icon: LayoutDashboard,
          }}
          groups={[
            {
              label: "Observe",
              items: NAV_ENTRIES.map((entry) => ({
                label: entry.label,
                href: entry.href,
                icon: entry.icon,
              })),
            },
          ]}
          footerItems={[]}
          currentPath={pathname}
          /*
          The menu, in the rail. **The identity and the sign-out are NOT
          here, and that is a fix rather than a preference.**

          `SideNav` does not render `accountSlot` below `lg` — its own doc
          says so, and ~52px has no room for an email address. Putting the
          signed-in identity here meant that at the e2e viewport (1000px)
          it was not on screen at all, and `dashboard.cy.ts`'s
          `cy.contains(staffEmail()).should("be.visible")` failed — taking
          the eight tests that follow it in that `testIsolation: false`
          sequence with it. The rail is navigation; who is signed in and the
          way out belong somewhere always visible.

          **There is deliberately no "Menu" button here.** One was, for one
          revision, and it was redundant: this slot renders only in the
          ≥1280px sidebar, where the rail already shows the whole nav tree
          and the account block — so the drawer it opened duplicated what
          was on screen, and the only thing it held that the rail did not
          was the theme control. The theme control is therefore in the slot
          directly and the trigger is gone. A button whose panel repeats the
          page is a button an operator learns to ignore.

          `<main>` still mounts `MoreMenu` behind `xl:hidden`, and that copy
          is load-bearing rather than a leftover: below `xl` this slot does
          not render at all, so the drawer is the only route to the theme
          control, and below 640px it is also the only full-label nav tree —
          `SideNav`'s pill shows four destinations and its own overflow.
        */
          accountSlot={
            <div className="flex flex-col gap-3">
              <SignedInBar
                email={email}
                merchantId={merchantId}
                signOut={signOut}
              />
              <ThemeSwitcher />
            </div>
          }
        />
      </div>
      {/*
        `smallScreen` is left at its default, `"floating"`. This app owns a
        drawer now (`MoreMenu`, below) but `side-nav.d.ts`'s `"off-canvas"`
        opt-in is for a caller that wraps `SideNav` ITSELF in a drawer to
        fill it — that is not this: `MoreMenu` renders its own plain nav
        list from `NAV_ENTRIES`, never `<SideNav>`, so none of that hazard
        applies here and `"floating"` stays the right default. `"off-canvas"`
        was tried here and measured wrong regardless: its `<nav>` is
        unconditionally `w-full`, and as a flex sibling of `<main>` that
        claimed the entire row below `lg` — `main` computed to 0px wide with
        the page scrolling sideways (a real render, real `app/globals.css`,
        375px: `main` width 0, `document.scrollWidth` 515 > `clientWidth`
        375).

        `"floating"` never draws a box of its own below `xl` — by design,
        so a caller who does own a drawer gets no second empty band — so
        nothing here reserves room for `FloatingRailPortal`'s pill, which
        is `position: fixed` and portaled to `document.body`, outside this
        flex row entirely. Measured on the same real render with no padding
        here: the bottom pill (`<640px`) sits at `left 135–241, top
        830–888` inside a 375×900 viewport, inside `main`'s own box; the
        vertical pill (`640–1279px`) sits at `left 12–64`, to the left of
        `main`'s content, which starts at `x=16`. Both genuinely overlap
        `main`.

        `pb-20` (80px) clears the bottom pill's height (58px) plus its
        `bottom-3` offset (12px) below `sm`; `sm:pl-20` (80px) clears the
        vertical pill's right edge (`x=64`) with room to spare from `sm` up
        to `xl`, where the real in-flow sidebar takes over and `xl:pl-0`
        gives the padding back.
      */}
      {/*
        The menu floats WITH the rail below `xl`, rather than sitting at the
        top of the content column.

        `SideNav`'s small-screen rails are `position: fixed` and portalled to
        `document.body`, and the component exposes no slot inside them —
        `accountSlot` renders only in the ≥1280px sidebar. So this is a
        sibling pinned to the same corner rather than a child of the rail,
        and it is styled by `Button` so it reads as part of that cluster.

        `left-3 bottom-3` is the rail's own geometry, not a guess: the
        vertical rail is `fixed top-1/2 left-3 w-[52px]` and the sub-640px
        pill is `fixed bottom-3 left-1/2 -translate-x-1/2`, so the
        bottom-left corner is empty at every width below `xl`. The icon-only
        trigger is ~44px wide, which fits inside the 80px gutter `<main>`
        already reserves with `sm:pl-20` — a labelled one would not, and
        would overlap the first column of the screen it navigates away from.

        Hidden from `xl` up: there the in-flow sidebar carries the nav tree,
        the account block and the theme control, so a trigger would open a
        drawer that repeats the page.
      */}
      <div className="fixed bottom-3 left-3 z-40 xl:hidden">
        <MoreMenu
          email={email}
          merchantId={merchantId}
          signOut={signOut}
          currentPath={pathname}
          compact
        />
      </div>
      <main className="min-w-0 flex-1 pb-20 sm:pb-0 sm:pl-20 xl:pl-0">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-6 p-6">
          {/*
            `SignedInBar` stays here, unconditionally — see the module doc
            above. `MoreMenu` is the new affordance beside it: a "More"
            button opening the drawer that holds the nav tree, the theme
            switcher, and a second `SignedInBar` for anyone who reached the
            drawer for a different reason and wants sign-out right there.
          */}
          <div className="flex flex-wrap items-center gap-4 xl:hidden">
            {/*
              Hidden below `sm`. On a 375px phone this block wrapped to three
              lines — address, merchant id, then "Sign out" — and pushed the
              screen's own heading below the fold before a single row was
              read. The drawer carries the same `SignedInBar`, so nothing is
              unreachable; it is one tap instead of zero.

              `sm` (640px) and not `md`, deliberately: `dashboard.cy.ts` runs
              at Cypress's default **1000px** viewport and asserts
              `cy.contains(staffEmail()).should("be.visible")` with eight
              tests chained behind it. 1000 is above `sm`, so that assertion
              still sees this copy.
            */}
            <div className="hidden sm:block">
              <SignedInBar
                email={email}
                merchantId={merchantId}
                signOut={signOut}
              />
            </div>
          </div>
          {children}
        </div>
      </main>
    </div>
  );
}
