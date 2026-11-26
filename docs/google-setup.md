# Getting the Google credentials

dirmoon uses two Google services. Both are optional, and each needs its own lines in `.env`:

| Lines in `.env` | What it turns on | Without it |
|---|---|---|
| `PAGESPEED_API_KEY` | The phone speed check in the Site Scan | The report says speed was not checked |
| `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` | "Connect Search Console": Google's own figures for where a site shows up | Positions come from DataForSEO instead |

Start with PageSpeed: it takes five minutes and every Existing Site research uses it. Search Console takes longer and only helps people who have already verified their site with Google.

Both are set up in the [Google Cloud console](https://console.cloud.google.com/). Menu names below come from Google's documentation as read on 26 November 2026; Google renames these pages from time to time, so a label may differ slightly.

## Before you start: a project

Everything in Google Cloud lives in a project.

1. Open <https://console.cloud.google.com/> and sign in with the Google account that should own dirmoon's credentials.
2. Click the project picker at the top of the page, then **New project**.
3. Name it (for example `dirmoon-dev`) and click **Create**.
4. Make sure that project is selected in the picker for every step below.

Neither service has a price list, and creating a project does not ask for a billing account. Google's pages don't state outright that no billing account is ever needed, so if the console asks for one, that is Google's requirement, not dirmoon's.

Google's OAuth policy asks for separate projects for testing and production. Use one project for your local setup now and create a second one when dirmoon goes live on its own domain.

## 1. PageSpeed key (`PAGESPEED_API_KEY`)

1. In the console's search bar, type **PageSpeed Insights API** and open it from the results (it is in **APIs & Services > Library**).
2. Click **Enable**.
3. Go to **APIs & Services > Credentials**.
4. Click **Create credentials > API key**.
5. In the form, restrict the key to one API: under API restrictions choose **Restrict key** and tick **PageSpeed Insights API**. A key that leaks can then be used for nothing else.
6. Leave the application restriction (IP addresses) off for local use: Google does not support localhost or internal addresses there. On a production server with a fixed outbound IP address, add that address.
7. Create the key and copy it.

Add it to `.env`:

```
export PAGESPEED_API_KEY=paste-the-key-here
```

Restart the server with `source .env && mix phx.server`. The next Site Scan checks phone speed.

**Quota.** Google's documentation gives no figure. Other sources mention about 25,000 requests a day; the real value for your project is on the API's **Quotas** page in the console. dirmoon normally makes one request per Site Scan; a check that failed is tried again when the scan is retried.

**If it doesn't work.** The report's phone section says why speed was not checked:

| What you see or what Google answers | Meaning | What to do |
|---|---|---|
| "Google's speed test isn't connected here" | No key reached the server, the key is wrong or deleted, or the API isn't enabled in the key's project. dirmoon shows the same line for all three | Check the `export` line, copy the key again from **Credentials**, check the API is enabled in the same project as the key, and that the key's restriction includes PageSpeed Insights API |
| "busy" in the report | The quota is used up | Wait, or check the Quotas page |
| "couldn't open your home page" | Google's test could not load the site | The site is down, slow, or blocks Google's test |

## 2. Search Console sign-in (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`)

This lets a dirmoon user click "Connect Search Console", sign in with Google and let dirmoon read their Search Console figures. dirmoon asks for read-only access and the account's e-mail address, nothing else.

### 2.1 Enable the API

1. In the console's search bar, type **Google Search Console API** and open it.
2. Click **Enable**.

### 2.2 Set up the consent screen

This is the screen Google shows people when they connect. It now lives under **Google Auth Platform** (older help pages call it "OAuth consent screen").

1. Open **Google Auth Platform** from the console menu or search bar.
2. On **Overview**, click **Get started**.
3. **App information:** an app name (`dirmoon`) and your support e-mail.
4. **Audience:** choose **External**. "Internal" only works for accounts inside a Google Workspace organisation. There is also a "Personal" option that only the creating account can use and that cannot be changed later; Google does not document its limits, so don't pick it.
5. **Contact information:** your e-mail.
6. Finish the wizard.

Then add the permission dirmoon asks for:

1. Open **Data Access**.
2. Add the scope `https://www.googleapis.com/auth/webmasters.readonly` (search for "Search Console"), along with `openid` and the e-mail scope if they aren't already listed.
3. Save.

### 2.3 Add yourself as a test user

A new app starts in **Testing** status. Only the accounts you list can connect.

1. Open **Audience**.
2. Under **Test users**, add the Google accounts that will connect (yours first). Up to 100 are allowed.

### 2.4 Create the client

1. Open **Clients** and click **Create client**.
2. Application type: **Web application**.
3. Under **Authorized redirect URIs**, add exactly:

   ```
   http://localhost:4000/app/search-console/callback
   ```

   It must match character for character. Plain `http` is allowed only for localhost; a real domain needs `https`.
4. Click **Create**.
5. Copy the **Client ID** and the **Client secret** from the dialog now. Google shows the secret only once; the dialog also offers it as a JSON download. If you lose it, open the client and use **Add secret** to make a new one.

Add both to `.env`:

```
export GOOGLE_CLIENT_ID=paste-the-client-id-here
export GOOGLE_CLIENT_SECRET=paste-the-client-secret-here
```

Restart the server with `source .env && mix phx.server`.

### 2.5 Connect

1. In dirmoon, start a new research in **Existing site** mode and click **Connect Search Console** under the address field.
2. Sign in with a Google account that is on your test users list.
3. Approve the read-only access.

For dirmoon to find any figures, that Google account must have the site in Search Console as a **Domain property** (the kind verified with a DNS record, shown as `example.com` without `https://`). A site added only as a "URL prefix" property (`https://example.com/`) is a different property, and dirmoon will find nothing for it. In that case the research still works: it takes positions from DataForSEO instead.

### 2.6 Limits while the app is in Testing

- **Connections stop working after 7 days.** Google's documentation says authorisations by a test user "expire seven days from the time of consent" for apps that ask for more than name and e-mail, which dirmoon does. dirmoon does not announce this: the new research screen still says Search Console is connected, and the research quietly takes positions from Google's results through DataForSEO instead. If the "Where your site shows up" step says its figures are "from Google's results" and not "from Search Console", disconnect and connect again.
- **Only listed test users can connect.** Anyone else gets `access_denied`.

That is fine for trying it yourself. For real users it is not.

### 2.7 Before real users connect

Two steps, both in Google Auth Platform, both for the production project and your real domain:

1. **Publish the app** (**Audience > Publish app**). This lifts the 7-day expiry. Until Google verifies the app, people see a warning that Google hasn't verified it, and Google caps an unverified app at 100 new users in total. Google explicitly allows staying unverified if you will have fewer than 100 users.
2. **Verification**, to remove the warning and the cap:
   - **Branding:** a home page and a privacy policy on your own domain, and that domain verified in Search Console by an owner or editor of the Cloud project. Google says this takes minutes, or two to three business days if someone reviews it by hand.
   - **Scope review:** a written reason for the Search Console permission and an unlisted YouTube video showing the connect flow with the client ID visible in the address bar. Google's documentation says this "can take up to 10 days". I could not confirm from a public Google page whether this scope counts as "sensitive"; the **Data Access** page shows its classification next to the scope.

The production client also needs its own redirect URI, `https://your-domain/app/search-console/callback`, and `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` set on the server.

### 2.8 If it doesn't work

| What you see | Meaning | What to do |
|---|---|---|
| "Search Console is not configured" in dirmoon | The two lines aren't reaching the server | Each line needs `export`; restart with `source .env && mix phx.server` |
| Google: `redirect_uri_mismatch` | The redirect URI in the client differs from the one dirmoon sent | Compare with step 2.4: same scheme, host, port and path, no trailing slash |
| Google: `access_denied` | The account isn't a test user | Add the account under **Audience > Test users** |
| "Could not connect to Search Console" in dirmoon | You pressed Cancel on Google's screen, or Google refused the sign-in | Try again and approve the access |
| The "Where your site shows up" step says "from Google's results" although Search Console is connected | The connection expired (the 7-day limit in Testing), access was removed in the Google account, or the account has no Domain property for that site. dirmoon doesn't yet say which on screen | Disconnect and connect again; check the site is a Domain property in Search Console; publish the app to stop the 7-day expiry |

## What ends up in `.env`

```
# Google PageSpeed Insights: phone speed in the Site Scan
export PAGESPEED_API_KEY=...

# Google Search Console sign-in (optional)
export GOOGLE_CLIENT_ID=...
export GOOGLE_CLIENT_SECRET=...
```

Keep `.env` out of git (it already is) and never paste these values into a chat, an issue or a screenshot. If one leaks, delete it in the console and create a new one.
