"""
Drug information service — 5 Free Online APIs + Local DB.

Online APIs (all free, no key required):
1. DDI Lab VN Search   — Vietnamese drug search (name, dosage form,
                         ingredients, manufacturer)
2. DDI Lab VN Interact — Drug-drug interactions (Vietnamese!)
3. OpenFDA NDC         — US drug: brand, generic, dosage_form
4. OpenFDA Label       — Usage, warnings, side effects
5. RxNorm (NIH)        — Generic name, RxCUI
6. DailyMed (NIH)      — FDA label link

Local DB:
- pill_information.csv — color, shape (VAIPE data)
- vaipe_drugs_kb.json  — VN drug names, brands
"""

import json
import html
import logging
import re
import unicodedata
from pathlib import Path
from typing import Any, Optional

import httpx

logger = logging.getLogger(__name__)

ROOT = Path(__file__).parent.parent.parent
DRUG_DB = ROOT / "server" / "data" / "drug_db.json"

# Free API endpoints (no key required)
DDI_VN_BASE = "https://ddi.lab.io.vn/api"
OPENFDA_BASE = "https://api.fda.gov/drug"
RXNORM_BASE = "https://rxnav.nlm.nih.gov/REST"
DAILYMED_BASE = (
    "https://dailymed.nlm.nih.gov/dailymed/services/v2"
)
PHARMACITY_SITEMAP = "https://www.pharmacity.vn/sitemaps/products.xml"
LONGCHAU_SITEMAP = "https://nhathuoclongchau.com.vn/sitemap_thuoc.xml"


class DrugService:
    """Hybrid drug lookup: local DB + free online APIs."""

    def __init__(self):
        self._db = {}
        self._cache = {}
        self._sitemap_cache = {}
        self._load_db()

    # ── Metadata enrichment profile ───────────────────

    async def enrich_metadata(self, name: str) -> dict[str, Any]:
        """
        Build a structured drug metadata profile from free sources.

        Sources used when available:
        - local DB
        - ddi.lab.io.vn
        - RxNorm / NDC properties
        - OpenFDA
        - DailyMed media
        """
        cache_key = f"meta:{self._normalize(name)}"
        if cache_key in self._cache:
            return self._cache[cache_key]

        profile = self._base_metadata_profile(name)

        local = self.lookup(name)
        if local:
            self._merge_local_entry(profile, local)

        vn_results = await self.search_vn(name, limit=3)
        if vn_results:
            self._merge_vn_entry(profile, vn_results[0])

        async with httpx.AsyncClient(timeout=12.0) as client:
            rxnorm = await self._rxnorm(client, name)
            if rxnorm:
                self._merge_rxnorm_entry(profile, rxnorm)

            openfda_ndc = await self._openfda_ndc(client, name)
            if openfda_ndc:
                self._merge_openfda_entry(profile, openfda_ndc)

            rxcui = profile["identifiers"].get("rxcui")
            if rxcui:
                ndcs = await self._rxnorm_all_ndcs(client, rxcui)
                for ndc in ndcs[:5]:
                    ndc_props = await self._rxnorm_ndc_properties(client, ndc)
                    if not ndc_props:
                        continue
                    self._merge_ndc_properties(profile, ndc_props)
                    if self._has_visual_metadata(profile):
                        break

            dailymed = await self._dailymed_with_media(client, name)
            if dailymed:
                self._merge_dailymed_entry(profile, dailymed)

            set_id = profile["identifiers"].get("setId")
            if set_id and not profile["images"]:
                media = await self._dailymed_media(client, set_id)
                if media:
                    self._merge_dailymed_entry(
                        profile,
                        {"setid": set_id, "images": media},
                    )

            should_scrape_vn = bool(vn_results or local or not profile["identifiers"].get("rxcui"))
            if should_scrape_vn and (not profile["images"] or not profile["dosageForm"] or not profile["manufacturer"]):
                vn_scrape = await self._vn_pharmacy_scrape(client, name)
                if vn_scrape:
                    self._merge_scraped_entry(profile, vn_scrape)

        profile["sources"] = list(dict.fromkeys(profile["sources"]))
        self._cache[cache_key] = profile
        return profile

    def _load_db(self):
        if DRUG_DB.exists():
            with open(DRUG_DB, encoding="utf-8") as f:
                self._db = json.load(f)
            logger.info(
                f"Drug DB loaded: {len(self._db)} entries")

    @staticmethod
    def _base_metadata_profile(name: str) -> dict[str, Any]:
        return {
            "queryName": name,
            "normalizedQuery": DrugService._normalize(name),
            "displayName": name,
            "brandName": "",
            "genericName": "",
            "dosageForm": "",
            "route": "",
            "manufacturer": "",
            "country": "",
            "registrationNumber": "",
            "activeIngredients": [],
            "packaging": "",
            "images": [],
            "notes": [],
            "sources": [],
            "identifiers": {
                "rxcui": "",
                "ndc": "",
                "setId": "",
            },
            "visual": {
                "colors": [],
                "colorCodes": [],
                "shapeCode": "",
                "shapeText": "",
                "imprint": [],
                "sizeMm": None,
                "score": None,
            },
        }

    @staticmethod
    def _append_unique(target: list, value: Any):
        if value in (None, "", []):
            return
        if value not in target:
            target.append(value)

    @staticmethod
    def _split_values(raw: str) -> list[str]:
        if not raw:
            return []
        parts = re.split(r"[;,/]|\s{2,}", str(raw))
        return [p.strip() for p in parts if p and p.strip()]

    def _merge_local_entry(self, profile: dict[str, Any], data: dict[str, Any]):
        if data.get("name") and not profile["genericName"]:
            profile["genericName"] = data["name"]
        if data.get("shape") and not profile["visual"]["shapeText"]:
            profile["visual"]["shapeText"] = data["shape"]
        if data.get("color"):
            self._append_unique(profile["visual"]["colors"], data["color"])
        self._append_unique(profile["sources"], "local_db")

    def _merge_vn_entry(self, profile: dict[str, Any], data: dict[str, Any]):
        ten_thuoc = data.get("tenThuoc", "")
        if ten_thuoc:
            profile["displayName"] = ten_thuoc
            if not profile["brandName"]:
                profile["brandName"] = ten_thuoc
        if data.get("soDangKy"):
            profile["registrationNumber"] = data["soDangKy"]
        if data.get("baoChe") and not profile["dosageForm"]:
            profile["dosageForm"] = data["baoChe"]
        if data.get("congTySx") and not profile["manufacturer"]:
            profile["manufacturer"] = data["congTySx"]
        if data.get("nuocSx") and not profile["country"]:
            profile["country"] = data["nuocSx"]
        if data.get("dongGoi") and not profile["packaging"]:
            profile["packaging"] = data["dongGoi"]
        for item in data.get("hoatChat", []):
            ingredient = {
                "name": item.get("ten", ""),
                "strength": item.get("nongDo", ""),
                "source": "ddi_vn",
            }
            if ingredient["name"] and ingredient not in profile["activeIngredients"]:
                profile["activeIngredients"].append(ingredient)
        self._append_unique(profile["sources"], "ddi_vn")

    def _merge_rxnorm_entry(self, profile: dict[str, Any], data: dict[str, Any]):
        if data.get("rxcui"):
            profile["identifiers"]["rxcui"] = str(data["rxcui"])
        rx_name = data.get("rxnorm_name", "")
        if rx_name and not profile["genericName"]:
            profile["genericName"] = rx_name
        self._append_unique(profile["sources"], "rxnorm")

    def _merge_openfda_entry(self, profile: dict[str, Any], data: dict[str, Any]):
        if data.get("fda_brand") and not profile["brandName"]:
            profile["brandName"] = data["fda_brand"]
        if data.get("fda_generic") and not profile["genericName"]:
            profile["genericName"] = data["fda_generic"]
        if data.get("ndc") and not profile["identifiers"]["ndc"]:
            profile["identifiers"]["ndc"] = data["ndc"]
        if data.get("dosage_form") and not profile["dosageForm"]:
            profile["dosageForm"] = data["dosage_form"]
        if data.get("route") and not profile["route"]:
            profile["route"] = data["route"]
        if data.get("manufacturer") and not profile["manufacturer"]:
            profile["manufacturer"] = data["manufacturer"]

        for item in data.get("active_ingredients", []):
            if isinstance(item, dict):
                ingredient = {
                    "name": item.get("name", ""),
                    "strength": item.get("strength", ""),
                    "source": "openfda",
                }
            else:
                ingredient = {
                    "name": str(item),
                    "strength": "",
                    "source": "openfda",
                }
            if ingredient["name"] and ingredient not in profile["activeIngredients"]:
                profile["activeIngredients"].append(ingredient)
        self._append_unique(profile["sources"], "openfda")

    def _merge_ndc_properties(self, profile: dict[str, Any], data: dict[str, Any]):
        ndc = data.get("ndc10") or data.get("ndcItem")
        if ndc and not profile["identifiers"]["ndc"]:
            profile["identifiers"]["ndc"] = str(ndc)

        set_id = data.get("splSetIdItem")
        if set_id and not profile["identifiers"]["setId"]:
            profile["identifiers"]["setId"] = str(set_id)

        for prop in data.get("propertyConceptList", {}).get("propertyConcept", []):
            name = prop.get("propName")
            value = prop.get("propValue")
            if not name or value in (None, ""):
                continue
            if name == "COLORTEXT":
                for color in self._split_values(value):
                    self._append_unique(profile["visual"]["colors"], color.lower())
            elif name == "COLOR":
                self._append_unique(profile["visual"]["colorCodes"], value)
            elif name == "IMPRINT_CODE":
                for imprint in self._split_values(value):
                    self._append_unique(profile["visual"]["imprint"], imprint)
            elif name == "SHAPE" and not profile["visual"]["shapeCode"]:
                profile["visual"]["shapeCode"] = str(value)
            elif name == "SIZE" and profile["visual"]["sizeMm"] is None:
                match = re.search(r"(\d+(?:\.\d+)?)", str(value))
                if match:
                    profile["visual"]["sizeMm"] = float(match.group(1))
            elif name == "SCORE" and profile["visual"]["score"] is None:
                match = re.search(r"(\d+(?:\.\d+)?)", str(value))
                if match:
                    score_value = float(match.group(1))
                    profile["visual"]["score"] = int(score_value) if score_value.is_integer() else score_value

        packaging_list = data.get("packagingList", {}).get("packaging", [])
        if packaging_list and not profile["packaging"]:
            profile["packaging"] = packaging_list[0]
        self._append_unique(profile["sources"], "rxnorm_ndc")

    def _merge_dailymed_entry(self, profile: dict[str, Any], data: dict[str, Any]):
        if data.get("setid") and not profile["identifiers"]["setId"]:
            profile["identifiers"]["setId"] = str(data["setid"])
        if data.get("title"):
            self._append_unique(profile["notes"], data["title"])
        if data.get("published_date"):
            self._append_unique(
                profile["notes"],
                f"DailyMed published: {data['published_date']}",
            )
        for item in data.get("images", []):
            if not item.get("url"):
                continue
            image_entry = {
                "url": item["url"],
                "name": item.get("name", ""),
                "source": "dailymed",
            }
            if image_entry not in profile["images"]:
                profile["images"].append(image_entry)
        self._append_unique(profile["sources"], "dailymed")

    def _merge_scraped_entry(self, profile: dict[str, Any], data: dict[str, Any]):
        if data.get("displayName") and profile["displayName"] == profile["queryName"]:
            profile["displayName"] = data["displayName"]
        if data.get("brandName") and not profile["brandName"]:
            profile["brandName"] = data["brandName"]
        if data.get("dosageForm") and not profile["dosageForm"]:
            profile["dosageForm"] = data["dosageForm"]
        if data.get("manufacturer") and not profile["manufacturer"]:
            profile["manufacturer"] = data["manufacturer"]
        if data.get("country") and not profile["country"]:
            profile["country"] = data["country"]
        if data.get("registrationNumber") and not profile["registrationNumber"]:
            profile["registrationNumber"] = data["registrationNumber"]
        if data.get("packaging") and not profile["packaging"]:
            profile["packaging"] = data["packaging"]
        for ingredient in data.get("activeIngredients", []):
            if ingredient.get("name") and ingredient not in profile["activeIngredients"]:
                profile["activeIngredients"].append(ingredient)
        for image in data.get("images", []):
            if image.get("url") and image not in profile["images"]:
                profile["images"].append(image)
        for note in data.get("notes", []):
            self._append_unique(profile["notes"], note)
        if data.get("scrapedUrl"):
            self._append_unique(profile["notes"], f"scraped_url: {data['scrapedUrl']}")
        self._append_unique(profile["sources"], data.get("source", "scraper"))

    @staticmethod
    def _has_visual_metadata(profile: dict[str, Any]) -> bool:
        visual = profile["visual"]
        return bool(
            visual["colors"]
            or visual["imprint"]
            or visual["shapeCode"]
            or visual["sizeMm"] is not None
        )

    # ── Local lookup (fast, offline) ─────────────────

    def lookup(self, name: str) -> Optional[dict]:
        """Look up drug from local DB."""
        if name in self._db:
            return self._db[name]

        norm = self._normalize(name)
        for key, val in self._db.items():
            if self._normalize(key) == norm:
                return val

        for key, val in self._db.items():
            nk = self._normalize(key)
            if norm in nk or nk in norm:
                return val
        return None

    def search(self, query: str, limit: int = 10) -> list:
        """Search local DB by partial name."""
        q = self._normalize(query)
        results = []
        for key, val in self._db.items():
            k = self._normalize(key)
            brand = self._normalize(val.get("brand", ""))
            if q in k or q in brand:
                results.append(val)
                if len(results) >= limit:
                    break
        return results

    # ══════════════════════════════════════════════════
    #  ONLINE APIs
    # ══════════════════════════════════════════════════

    # ── 1. DDI Lab VN — Vietnamese drug search ───────

    async def search_vn(
        self, query: str, limit: int = 10
    ) -> list:
        """
        Search Vietnamese drugs via ddi.lab.io.vn.

        Returns: list of VN drugs with name, ingredients,
                 dosage form (shape), manufacturer.
        """
        try:
            async with httpx.AsyncClient(
                timeout=10.0
            ) as client:
                url = f"{DDI_VN_BASE}/drugs/search-detailed"
                resp = await client.get(url, params={
                    "q": query, "page": 1, "limit": limit
                })
                if resp.status_code != 200:
                    return []

                data = resp.json()
                results = []
                for d in data.get("drugs", []):
                    entry = {
                        "tenThuoc": d.get(
                            "tenThuoc", "").strip(),
                        "soDangKy": d.get("soDangKy", ""),
                        "hoatChat": [
                            {
                                "ten": h.get(
                                    "tenHoatChat", ""),
                                "nongDo": h.get(
                                    "nongDo", ""),
                            }
                            for h in d.get("hoatChat", [])
                        ],
                        "baoChe": d.get("baoChe", ""),
                        "dongGoi": d.get("dongGoi", ""),
                        "phanLoai": d.get("phanLoai", ""),
                        "congTySx": d.get("congTySx", ""),
                        "nuocSx": d.get("nuocSx", ""),
                        "nhomThuoc": d.get(
                            "nhomThuoc", ""),
                        "source": "ddi.lab.io.vn",
                    }
                    results.append(entry)
                return results
        except Exception as e:
            logger.warning(f"DDI VN search error: {e}")
            return []

    async def suggest_vn(self, query: str) -> list:
        """
        Drug name autocomplete from ddi.lab.io.vn.

        Returns: list of drug name strings.
        """
        try:
            async with httpx.AsyncClient(
                timeout=5.0
            ) as client:
                url = f"{DDI_VN_BASE}/drugs/search"
                resp = await client.get(
                    url, params={"q": query})
                if resp.status_code != 200:
                    return []
                return resp.json()
        except Exception as e:
            logger.warning(f"DDI VN suggest error: {e}")
            return []

    async def interactions(
        self, ingredient: str
    ) -> dict:
        """
        Get drug interactions from ddi.lab.io.vn.

        Args:
            ingredient: Active ingredient name
                        (e.g. "paracetamol")

        Returns: dict with interaction lists
                 grouped by severity.
        """
        try:
            async with httpx.AsyncClient(
                timeout=10.0
            ) as client:
                url = (
                    f"{DDI_VN_BASE}"
                    f"/interactions/by-active-ingredient"
                )
                resp = await client.get(url, params={
                    "ingredientName": ingredient
                })
                if resp.status_code != 200:
                    return {}
                data = resp.json()
                # Simplify the response
                interactions = data.get(
                    "interactions", {})
                simplified = {}
                for severity, items in interactions.items():
                    simplified[severity] = [
                        {
                            "thuoc1": i.get(
                                "hoatChat1", ""),
                            "thuoc2": i.get(
                                "hoatChat2", ""),
                            "canhBao": i.get(
                                "canhBao", ""),
                        }
                        for i in items[:20]
                    ]
                return {
                    "ingredient": ingredient,
                    "total": data.get(
                        "totalInteractions", 0),
                    "interactions": simplified,
                }
        except Exception as e:
            logger.warning(
                f"DDI VN interactions error: {e}")
            return {}

    # ── 2. OpenFDA — US drug info ────────────────────

    async def search_online(
        self, query: str, limit: int = 5
    ) -> list:
        """
        Search drugs online using OpenFDA NDC.

        Returns list of drug entries with brand, generic,
        dosage_form, active ingredients.
        """
        try:
            async with httpx.AsyncClient(
                timeout=10.0
            ) as client:
                clean = re.sub(r'[-_]', ' ', query)
                url = f"{OPENFDA_BASE}/ndc.json"
                resp = await client.get(url, params={
                    "search": (
                        f'brand_name:"{clean}"'
                        f'+generic_name:"{clean}"'
                    ),
                    "limit": limit,
                })
                if resp.status_code != 200:
                    resp = await client.get(url, params={
                        "search": (
                            f'brand_name:"{clean}"'
                        ),
                        "limit": limit,
                    })
                if resp.status_code != 200:
                    return []

                data = resp.json()
                results = []
                for item in data.get("results", []):
                    entry = {
                        "name": item.get(
                            "generic_name", ""),
                        "brand": item.get(
                            "brand_name", ""),
                        "dosage_form": item.get(
                            "dosage_form", ""),
                        "route": ", ".join(
                            item.get("route", [])),
                        "manufacturer": item.get(
                            "labeler_name", ""),
                        "source": "openfda",
                    }
                    ingredients = item.get(
                        "active_ingredients", [])
                    if ingredients:
                        entry["active_ingredients"] = [
                            {
                                "name": i.get("name"),
                                "strength": i.get(
                                    "strength"),
                            }
                            for i in ingredients
                        ]
                    openfda = item.get("openfda", {})
                    if "pharm_class" in openfda:
                        entry["pharm_class"] = openfda[
                            "pharm_class"]
                    results.append(entry)
                return results
        except Exception as e:
            logger.warning(
                f"OpenFDA search error: {e}")
            return []

    # ── 3. Full online lookup (all APIs) ─────────────

    async def lookup_online(self, name: str) -> dict:
        """
        Full online lookup using all APIs.

        Combines: local DB + OpenFDA + RxNorm + DailyMed.
        """
        cache_key = self._normalize(name)
        if cache_key in self._cache:
            return self._cache[cache_key]

        result = self.lookup(name) or {"name": name}

        async with httpx.AsyncClient(
            timeout=10.0
        ) as client:
            ndc = await self._openfda_ndc(client, name)
            if ndc:
                result.update(ndc)

            label = await self._openfda_label(
                client, name)
            if label:
                result.update(label)

            rxnorm = await self._rxnorm(client, name)
            if rxnorm:
                result.update(rxnorm)

            dailymed = await self._dailymed(
                client, name)
            if dailymed:
                result.update(dailymed)

        result["source_online"] = True
        self._cache[cache_key] = result
        return result

    # ── API helpers ──────────────────────────────────

    async def _openfda_ndc(self, client, name):
        """OpenFDA NDC: brand, generic, dosage_form."""
        try:
            clean = re.sub(r'[-_]', ' ', name)
            clean = re.sub(
                r'\d+\s*mg', '', clean,
                flags=re.I).strip()
            url = f"{OPENFDA_BASE}/ndc.json"
            resp = await client.get(url, params={
                "search": f'brand_name:"{clean}"',
                "limit": 1
            })
            if resp.status_code != 200:
                resp = await client.get(url, params={
                    "search": (
                        f'generic_name:"{clean}"'
                    ),
                    "limit": 1
                })
            if resp.status_code != 200:
                return {}

            items = resp.json().get("results", [])
            if not items:
                return {}

            item = items[0]
            result = {
                "fda_brand": item.get(
                    "brand_name", ""),
                "fda_generic": item.get(
                    "generic_name", ""),
                "dosage_form": item.get(
                    "dosage_form", ""),
                "route": ", ".join(
                    item.get("route", [])),
                "manufacturer": item.get(
                    "labeler_name", ""),
            }
            if item.get("product_ndc"):
                result["ndc"] = item.get("product_ndc")
            elif item.get("package_ndc"):
                result["ndc"] = item.get("package_ndc")
            ingredients = item.get(
                "active_ingredients", [])
            if ingredients:
                result["active_ingredients"] = [
                    f"{i['name']} ({i['strength']})"
                    for i in ingredients
                ]
            openfda = item.get("openfda", {})
            if "pharm_class" in openfda:
                result["pharm_class"] = openfda[
                    "pharm_class"]
            return result
        except Exception as e:
            logger.warning(f"OpenFDA NDC err: {e}")
            return {}

    async def _openfda_label(self, client, name):
        """OpenFDA Label: usage, warnings, side_effects."""
        try:
            clean = re.sub(r'[-_]', ' ', name)
            clean = re.sub(
                r'\d+\s*mg', '', clean,
                flags=re.I).strip()
            url = f"{OPENFDA_BASE}/label.json"
            resp = await client.get(url, params={
                "search": (
                    f'openfda.brand_name:"{clean}"'
                ),
                "limit": 1
            })
            if resp.status_code != 200:
                resp = await client.get(url, params={
                    "search": (
                        f'openfda.generic_name:'
                        f'"{clean}"'
                    ),
                    "limit": 1
                })
            if resp.status_code != 200:
                return {}

            items = resp.json().get("results", [])
            if not items:
                return {}

            item = items[0]
            result = {}
            fields = {
                "purpose": "purpose",
                "indications_and_usage": "usage",
                "warnings": "warnings",
                "dosage_and_administration": (
                    "dosage_info"),
                "adverse_reactions": "side_effects",
            }
            for fda_key, our_key in fields.items():
                val = item.get(fda_key)
                if val and isinstance(val, list):
                    text = val[0]
                    text = re.sub(
                        r'\s+', ' ', text).strip()
                    if len(text) > 500:
                        text = text[:497] + "..."
                    result[our_key] = text
            return result
        except Exception as e:
            logger.warning(
                f"OpenFDA Label err: {e}")
            return {}

    async def _rxnorm(self, client, name):
        """RxNorm: generic name, RxCUI."""
        try:
            clean = re.sub(r'[-_]', ' ', name)
            clean = re.sub(
                r'\d+\s*mg', '', clean,
                flags=re.I).strip()
            url = f"{RXNORM_BASE}/drugs.json"
            resp = await client.get(
                url, params={"name": clean})
            if resp.status_code != 200:
                return {}

            groups = resp.json().get(
                "drugGroup", {}).get(
                "conceptGroup", [])
            tty_priority = ["SBD", "SCD", "BPCK", "GPCK"]
            for tty in tty_priority:
                for group in groups:
                    if group.get("tty") != tty:
                        continue
                    props = group.get("conceptProperties", [])
                    if props:
                        return {
                            "rxcui": props[0].get("rxcui"),
                            "rxnorm_name": props[0].get("name"),
                            "tty": tty,
                        }
            return {}
        except Exception as e:
            logger.warning(f"RxNorm err: {e}")
            return {}

    async def _rxnorm_all_ndcs(self, client, rxcui: str) -> list[str]:
        """RxNorm: all NDCs associated with an RxCUI."""
        try:
            url = f"{RXNORM_BASE}/rxcui/{rxcui}/allndcs.json"
            resp = await client.get(url)
            if resp.status_code != 200:
                return []
            ndc_times = resp.json().get("ndcConcept", {}).get("ndcTime", [])
            ndcs = []
            for item in ndc_times:
                for ndc in item.get("ndc", []):
                    if ndc and ndc not in ndcs:
                        ndcs.append(ndc)
            return ndcs
        except Exception as e:
            logger.warning(f"RxNorm all NDCs err: {e}")
            return []

    async def _rxnorm_ndc_properties(self, client, ndc: str) -> dict[str, Any]:
        """RxNorm: pill physical properties for one NDC."""
        try:
            url = f"{RXNORM_BASE}/ndcproperties.json"
            resp = await client.get(url, params={"id": ndc})
            if resp.status_code != 200:
                return {}
            items = resp.json().get("ndcPropertyList", {}).get("ndcProperty", [])
            return items[0] if items else {}
        except Exception as e:
            logger.warning(f"RxNorm NDC properties err: {e}")
            return {}

    async def _dailymed(self, client, name):
        """DailyMed: FDA label link."""
        try:
            clean = re.sub(r'[-_]', ' ', name)
            url = f"{DAILYMED_BASE}/spls.json"
            resp = await client.get(url, params={
                "drug_name": clean, "pagesize": 1
            })
            if resp.status_code != 200:
                return {}

            spls = resp.json().get("data", [])
            if not spls:
                return {}

            setid = spls[0].get("setid")
            return {
                "dailymed_url": (
                    "https://dailymed.nlm.nih.gov/"
                    "dailymed/drugInfo.cfm"
                    f"?setid={setid}"
                ),
            }
        except Exception as e:
            logger.warning(f"DailyMed err: {e}")
            return {}

    async def _dailymed_with_media(self, client, name) -> dict[str, Any]:
        """DailyMed: search SPL and fetch media images when available."""
        try:
            clean = re.sub(r'[-_]', ' ', name)
            url = f"{DAILYMED_BASE}/spls.json"
            resp = await client.get(url, params={"drug_name": clean, "pagesize": 1})
            if resp.status_code != 200:
                return {}

            spls = resp.json().get("data", [])
            if not spls:
                return {}

            first = spls[0]
            set_id = first.get("setid")
            result = {
                "setid": set_id,
                "title": first.get("title", ""),
                "published_date": first.get("published_date", ""),
                "images": [],
            }
            if set_id:
                result["images"] = await self._dailymed_media(client, set_id)
            return result
        except Exception as e:
            logger.warning(f"DailyMed media lookup err: {e}")
            return {}

    async def _dailymed_media(self, client, set_id: str) -> list[dict[str, Any]]:
        try:
            url = f"{DAILYMED_BASE}/spls/{set_id}/media.json"
            resp = await client.get(url)
            if resp.status_code != 200:
                return []
            media = resp.json().get("data", {}).get("media", [])
            images = []
            for item in media:
                if item.get("mime_type", "").startswith("image/"):
                    images.append(
                        {
                            "url": item.get("url", ""),
                            "name": item.get("name", ""),
                        }
                    )
            return images
        except Exception as e:
            logger.warning(f"DailyMed media err: {e}")
            return []

    async def _vn_pharmacy_scrape(self, client, query: str) -> dict[str, Any]:
        """Fallback scraper for Vietnamese drug pages using public sitemaps."""
        longchau_url = await self._find_best_sitemap_match(
            client,
            LONGCHAU_SITEMAP,
            query,
            site="longchau",
        )
        if longchau_url:
            data = await self._scrape_longchau_product(client, longchau_url)
            if data:
                return data

        pharmacity_url = await self._find_best_sitemap_match(
            client,
            PHARMACITY_SITEMAP,
            query,
            site="pharmacity",
        )
        if pharmacity_url:
            data = await self._scrape_pharmacity_product(client, pharmacity_url)
            if data:
                return data

        return {}

    async def _find_best_sitemap_match(
        self,
        client,
        sitemap_url: str,
        query: str,
        site: str,
    ) -> Optional[str]:
        urls = await self._load_sitemap_urls(client, sitemap_url)
        if not urls:
            return None

        scored: list[tuple[float, str]] = []
        for url in urls:
            if site == "longchau" and "/thuoc/" not in url:
                continue
            score = self._score_product_url(query, url)
            if score > 0:
                scored.append((score, url))

        scored.sort(key=lambda item: (-item[0], len(item[1])))
        return scored[0][1] if scored else None

    async def _load_sitemap_urls(self, client, sitemap_url: str) -> list[str]:
        cache_key = f"sitemap:{sitemap_url}"
        if cache_key in self._sitemap_cache:
            return self._sitemap_cache[cache_key]

        try:
            resp = await client.get(sitemap_url)
            if resp.status_code != 200:
                return []
            urls = re.findall(r"<loc>(.*?)</loc>", resp.text)
            self._sitemap_cache[cache_key] = urls
            return urls
        except Exception as exc:
            logger.warning("Sitemap load err (%s): %s", sitemap_url, exc)
            return []

    def _score_product_url(self, query: str, url: str) -> float:
        slug = url.rsplit("/", 1)[-1].replace(".html", "")
        slug_norm = self._normalize_loose(slug)
        query_norm = self._normalize_loose(query)
        if not query_norm:
            return 0.0

        score = 0.0
        if query_norm in slug_norm:
            score += 4.0

        query_tokens = self._query_tokens(query)
        slug_tokens = self._query_tokens(slug.replace("-", " "))

        overlap = sum(1 for token in query_tokens if token in slug_tokens)
        score += overlap * 1.4

        if query_tokens and query_tokens[0] in slug_tokens:
            score += 0.8

        if overlap and len(slug_tokens) <= len(query_tokens) + 6:
            score += 0.4

        return score

    async def _scrape_pharmacity_product(self, client, url: str) -> dict[str, Any]:
        try:
            resp = await client.get(url)
            if resp.status_code != 200:
                return {}
            return self._parse_pharmacity_html(resp.text, url)
        except Exception as exc:
            logger.warning("Pharmacity scrape err: %s", exc)
            return {}

    async def _scrape_longchau_product(self, client, url: str) -> dict[str, Any]:
        try:
            resp = await client.get(url)
            if resp.status_code != 200:
                return {}
            return self._parse_longchau_html(resp.text, url)
        except Exception as exc:
            logger.warning("Long Chau scrape err: %s", exc)
            return {}

    def _parse_pharmacity_html(self, raw_html: str, url: str) -> dict[str, Any]:
        text = html.unescape(raw_html)
        images = self._extract_og_images(text, source="pharmacity")
        active = self._split_ingredients(self._extract_label_value(text, "Hoạt chất"))
        return {
            "source": "pharmacity",
            "scrapedUrl": url,
            "displayName": self._extract_og_text(text, "og:title") or self._extract_title(text),
            "brandName": self._extract_inline_value(text, "Thương hiệu:"),
            "dosageForm": self._extract_label_value(text, "Dạng bào chế"),
            "manufacturer": self._extract_label_value(text, "Nhà sản xuất"),
            "country": self._extract_label_value(text, "Nơi sản xuất"),
            "registrationNumber": self._extract_inline_value(text, "Số đăng ký:"),
            "packaging": self._extract_label_value(text, "Quy cách"),
            "activeIngredients": [
                {"name": item, "strength": "", "source": "pharmacity"}
                for item in active
            ],
            "images": images,
            "notes": [],
        }

    def _parse_longchau_html(self, raw_html: str, url: str) -> dict[str, Any]:
        text = html.unescape(raw_html)
        next_product = self._extract_longchau_next_product(text)
        if next_product:
            ingredients = []
            for item in next_product.get("ingredient", []) or []:
                ingredient_name = str(item.get("name") or item.get("ingredientName") or "").strip()
                if ingredient_name:
                    ingredients.append(
                        {
                            "name": ingredient_name,
                            "strength": str(item.get("content") or item.get("strength") or "").strip(),
                            "source": "longchau",
                        }
                    )

            images = []
            primary = next_product.get("primaryImage")
            if primary:
                images.append({"url": primary, "name": primary.rsplit("/", 1)[-1], "source": "longchau"})
            for image_url in next_product.get("secondaryImages", []) or []:
                entry = {"url": image_url, "name": image_url.rsplit("/", 1)[-1], "source": "longchau"}
                if entry not in images:
                    images.append(entry)

            return {
                "source": "longchau",
                "scrapedUrl": url,
                "displayName": next_product.get("webName") or next_product.get("name") or "",
                "brandName": str(next_product.get("brand") or "").strip(),
                "dosageForm": str(next_product.get("dosageForm") or "").strip(),
                "manufacturer": str(next_product.get("producer") or "").strip(),
                "country": str(next_product.get("manufactor") or "").strip(),
                "registrationNumber": str(next_product.get("registNum") or "").strip(),
                "packaging": str(next_product.get("specification") or "").strip(),
                "activeIngredients": ingredients,
                "images": images,
                "notes": [note for note in [f"sku: {next_product.get('sku', '')}".strip()] if note and note != 'sku:'],
            }

        active_text = self._extract_longchau_ingredient(text)
        active = self._split_ingredients(active_text)
        notes = []
        sku = self._extract_longchau_sku(text)
        if sku:
            notes.append(f"sku: {sku}")

        return {
            "source": "longchau",
            "scrapedUrl": url,
            "displayName": self._extract_og_text(text, "og:title") or self._extract_title(text),
            "brandName": self._extract_inline_value(text, "Thương hiệu:"),
            "dosageForm": self._extract_longchau_detail_value(text, "Dạng bào chế"),
            "manufacturer": self._extract_longchau_detail_value(text, "Nhà sản xuất"),
            "country": self._extract_longchau_detail_value(text, "Nước sản xuất"),
            "registrationNumber": self._extract_longchau_detail_value(text, "Số đăng ký"),
            "packaging": self._extract_longchau_detail_value(text, "Quy cách"),
            "activeIngredients": [
                {"name": item, "strength": "", "source": "longchau"}
                for item in active
            ],
            "images": self._extract_og_images(text, source="longchau"),
            "notes": notes,
        }

    def _extract_longchau_next_product(self, text: str) -> dict[str, Any]:
        match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', text, flags=re.S)
        if not match:
            return {}
        try:
            payload = json.loads(match.group(1))
        except Exception:
            return {}
        product = payload.get("props", {}).get("pageProps", {}).get("product", {})
        return product if isinstance(product, dict) else {}

    def _extract_title(self, text: str) -> str:
        match = re.search(r"<title[^>]*>(.*?)</title>", text, flags=re.I | re.S)
        if not match:
            return ""
        return re.sub(r"\s+", " ", match.group(1)).strip()

    def _extract_og_text(self, text: str, property_name: str) -> str:
        pattern = rf'<meta[^>]+property="{re.escape(property_name)}"[^>]+content="([^"]+)"'
        match = re.search(pattern, text, flags=re.I)
        return match.group(1).strip() if match else ""

    def _extract_og_images(self, text: str, source: str) -> list[dict[str, Any]]:
        urls = re.findall(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"', text, flags=re.I)
        images = []
        for url in urls:
            entry = {"url": url, "name": url.rsplit("/", 1)[-1], "source": source}
            if entry not in images:
                images.append(entry)
        return images

    def _extract_inline_value(self, text: str, label: str) -> str:
        patterns = [
            rf"{re.escape(label)}\s*</span>\s*<span[^>]*>([^<\n]+)",
            rf"{re.escape(label)}\s*(?:</[^>]+>|<[^>]+>)+\s*([^<\n]+)",
            rf"{re.escape(label)}\s*([^<\n]+)",
        ]
        for pattern in patterns:
            match = re.search(pattern, text, flags=re.I)
            if match:
                return match.group(1).strip()
        return ""

    def _extract_label_value(self, text: str, label: str) -> str:
        pattern = (
            rf">{re.escape(label)}(?:<!--.*?-->)?:</p><div[^>]*>"
            rf"([^<]+)"
        )
        match = re.search(pattern, text, flags=re.I | re.S)
        return re.sub(r"\s+", " ", match.group(1)).strip() if match else ""

    def _extract_longchau_detail_value(self, text: str, label: str) -> str:
        pattern = (
            rf">{re.escape(label)}</p></div><div[^>]*>(?:<div[^>]*>)?"
            rf"(?:<span[^>]*>)?([^<]+)"
        )
        match = re.search(pattern, text, flags=re.I | re.S)
        return re.sub(r"\s+", " ", match.group(1)).strip() if match else ""

    def _extract_longchau_ingredient(self, text: str) -> str:
        match = re.search(
            r">Thành phần</p></div><div[^>]*><div><div[^>]*><div[^>]*><span>([^<]+)</span>",
            text,
            flags=re.I | re.S,
        )
        return re.sub(r"\s+", " ", match.group(1)).strip() if match else ""

    def _extract_longchau_sku(self, text: str) -> str:
        match = re.search(r'data-test-id="sku"[^>]*>([^<]+)</span>', text, flags=re.I)
        return match.group(1).strip() if match else ""

    def _split_ingredients(self, raw: str) -> list[str]:
        return [
            part.strip()
            for part in re.split(r"[;,]", raw)
            if part and part.strip()
        ]

    @staticmethod
    def _normalize_loose(s: str) -> str:
        plain = unicodedata.normalize("NFKD", s)
        plain = "".join(ch for ch in plain if not unicodedata.combining(ch))
        plain = plain.lower().replace("đ", "d")
        return re.sub(r"[^a-z0-9]+", " ", plain).strip()

    def _query_tokens(self, s: str) -> list[str]:
        tokens = self._normalize_loose(s).split()
        filtered = []
        for token in tokens:
            if token in {"mg", "ml", "vi", "x", "hop", "goi", "vien", "thuoc"}:
                continue
            if token.isdigit() and len(token) <= 2:
                continue
            filtered.append(token)
        return filtered

    # ── Utilities ────────────────────────────────────

    @staticmethod
    def _normalize(s: str) -> str:
        return re.sub(
            r'[^a-z0-9]', '', s.lower().strip())

    def get_all(self) -> dict:
        return self._db

    def count(self) -> int:
        return len(self._db)
