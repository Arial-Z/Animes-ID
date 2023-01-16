import json, requests
from datetime import datetime
from lxml import html

AniDBIDs = html.fromstring(requests.get("https://raw.githubusercontent.com/Anime-Lists/anime-lists/master/anime-list-master.xml").content)
Manami = requests.get("https://raw.githubusercontent.com/manami-project/anime-offline-database/master/anime-offline-database.json").json()

anime_dicts = {}

for anime in AniDBIDs.xpath("//anime"):
    anidb_id = str(anime.xpath("@anidbid")[0])
    if not anidb_id:
        continue
    anidb_id = int(anidb_id[1:]) if anidb_id[0] == "a" else int(anidb_id)
    anime_dict = {}
    tvdb_id = str(anime.xpath("@tvdbid")[0])
    if tvdb_id.isdigit():
        anime_dict["tvdb_id"] = int(tvdb_id)
        tvdb_season = str(anime.xpath("@defaulttvdbseason")[0])
        if str(tvdb_season) == "a":
            tvdb_season = 1
        if tvdb_id.isdigit():
            anime_dict["tvdb_season"] = int(tvdb_season)
            if int(tvdb_season) != 0:
                tvdb_epoffset = str(anime.xpath("@episodeoffset")[0])
                if tvdb_epoffset.isdigit() :
                    anime_dict["tvdb_epoffset"] = int(tvdb_epoffset)
                else:
                    tvdb_epoffset = 0
                    anime_dict["tvdb_epoffset"] = int(tvdb_epoffset)
    imdb_id = str(anime.xpath("@imdbid")[0])
    if imdb_id.startswith("tt"):
        anime_dict["imdb_id"] = imdb_id
    anime_dicts[anidb_id] = anime_dict

for anime in Manami["data"]:
    if "sources" not in anime:
        continue

    anidb_id = None
    mal_id = None
    anilist_id = None
    for source in anime["sources"]:
        if "anidb.net" in source:
            anidb_id = int(source.partition("anime/")[2])
        elif "myanimelist" in source:
            mal_id = int((source.partition("anime/")[2]))
        elif "anilist.co" in source:
            anilist_id = int((source.partition("anime/")[2]))
    if anidb_id and anidb_id in anime_dicts:
        if mal_id:
            anime_dicts[anidb_id]["mal_id"] = mal_id
        if anilist_id:
            anime_dicts[anidb_id]["anilist_id"] = anilist_id

with open("pmm_edits.json", "r") as f:
    for anidb_id, ids in json.load(f).items():
        anidb_id = int(anidb_id)
        if anidb_id in anime_dicts:
            for attr in ["tvdb_id","tvdb_season","tvdb_epoffset", "mal_id", "anilist_id", "imdb_id"]:
                if attr in ids:
                    anime_dicts[anidb_id][attr] = ids[attr]

with open("pmm_anime_ids.json", "w") as write:
    json.dump(anime_dicts, write, indent=2)