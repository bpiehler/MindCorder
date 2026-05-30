# Phase 6.3: Responsive Hybrid Semantic Search — Implementation Plan

This plan details the design, architecture, and implementation steps for **Phase 6.3: Semantic Vector Search**. It addresses the need for a highly responsive, offline-first search system directly integrated into the MindCorder home screen, enabling instant card filtering as the user types, combined with concept-level semantic matching.

---

## 1. Architectural Principles

### The Challenge of Pure Neural Embeddings "As-You-Type"
Calculating full-dimensional deep neural embeddings (e.g., OpenAI `text-embedding-3-small` or Gemini `text-embedding-004`) for *every single keystroke* as the user types:
1. **Requires Internet & API Keys**: Fails when offline or without keys configured.
2. **Heavy Latency (150ms - 500ms)**: Introducing network round-trips breaks the "highly responsive" requirement.
3. **API Rate Limiting & Cost**: Keystroke-level API spamming would exhaust rate limits instantly.

### The Resolution: A Hybrid VSM Engine
To deliver a 60 FPS "disappear as you type" animation coupled with genuine concept matching, we will construct a **local Hybrid Vector Space Model (VSM)** written in pure Dart:
```
  [ User Types Query ] ─────────────────────────┐
         │                                       │
         ▼ (Instant <0.5ms)                      ▼ (Debounced 400ms)
┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│  TF-IDF Jaccard Token Matcher   │   │    Semantic Concept Expansion    │
│  - Filters notes dynamically     │   │   - Resolves synonyms & related  │
│  - Keystroke-reactive filtering  │   │     terms (e.g. grocery -> milk) │
│  - Instantly hides non-matches   │   │   - Adjusts relevance weightings │
└──────────────────────────────────┘   └──────────────────────────────────┘
         │                                       │
         └───────────────────┬───────────────────┘
                             ▼
             ┌───────────────────────────────┐
             │   Sorted Timeline Groups      │
             │   - Renders matching notes    │
             │   - Displays similarity score │
             └───────────────────────────────┘
```

1. **Reactive Keyword / Token Filter (Keystroke Level)**:
   - Evaluates note titles, body summaries, and raw transcripts.
   - Hides non-matching notes instantly (<1ms latency) to guarantee visual responsiveness.
2. **Local TF-IDF Vector Space Model**:
   - Represents each note as a term frequency vector in a local vocabulary index.
   - Computes **Cosine Similarity** between the search query vector and note vectors to rank results by conceptual relevance.
3. **Semantic Concept/Synonym Expansion**:
   - Automatically maps related concepts (e.g., `groceries` ↔ `milk, supermarket, shopping, food`, `work` ↔ `meeting, project, boss, manager, tasks, email`).
   - Dynamically injects expanded concept terms into the query vector with custom decay weights, ensuring "milk" matches the query "groceries" even without exact word overlap.

---

## 2. Core Components

### 2.1 The Search Engine (`search_helper.dart`)
Create a dedicated `SearchHelper` utility containing:
- **`TokenMapper`**: Clean and normalize text (lowercasing, punctuation stripping, stop-word removal).
- **`TFIDFEngine`**: Build a vocabulary dictionary across all notes dynamically, mapping Term Frequency (TF) and Inverse Document Frequency (IDF) weights.
- **`SemanticDictionary`**: A pre-compiled JSON-style synonym thesaurus for common concept mappings.
- **`CosineSimilarity`**: Compares the query vector to note vectors.

### 2.2 Database Schema Alignment
No complex migrations or SQL schema changes are required! The search engine will dynamically index the active text fields (`summaryTitle`, `summaryBody`, `rawText`) in memory or on-the-fly. This guarantees 100% reliability, zero database locking, and instant execution.

### 2.3 Elegant UI/UX Integration (`note_list_page.dart`)
- **Glassmorphic Search Bar**: 
  - Positioned as a pinned sliver below the connection indicator.
  - Transparent blur backing (`BackdropFilter` with `sigma: 8.0`) matching the premium glassmorphic headers.
  - Smooth expansion micro-animations when focused.
  - Includes a clear `IconButton` to reset active queries.
- **Fluid Timeline Animation**:
  - The notes stream will filter list entries in real-time.
  - Flutter's reactive widget updates will automatically trigger slide/fade transitions as notes disappear or reappear in their timeline groupings.
  - Headers dynamically dissolve when all underlying notes are filtered out.
- **Match Indicator**:
  - Displays a subtle matching indicator (e.g. `92% match` or dynamic search icon) only when active search queries are present, providing premium visual feedback.

---

## 3. Plan & Verification Steps

### Step 1: Implement the Search Engine Core
- Develop `search_helper.dart` in `companion/lib/src/ui/search_helper.dart`.
- Implement `TFIDFEngine` and semantic concept mapping algorithms.
- Implement tests in `companion/test/unit/search_helper_test.dart` asserting correct tf-idf vector ranking, semantic expansion behavior, and edge-case handling (empty inputs, punctuation).

### Step 2: Integrate search box in NoteListPage
- Add a Search State variable (`_searchQuery`) to `_NoteListPageState`.
- Incorporate a sleek search text field into the sliver timeline.
- Hook the text controller up to update `_searchQuery` in real-time, executing the fast filter synchronously.
- Show similarity match scores on note cards when search is active.

### Step 3: Run Unit & Widget Tests
- Verify all unit tests compile and run flawlessly (`flutter test`).
- Ensure no layout compilation warnings or performance overhead is introduced.

### Step 4: Sideload & Verify manually on device
- Verify "as-you-type" cards disappear smoothly.
- Test semantic search (e.g. typing "shopping" or "groceries" and observing note cards with "milk" or "supermarket" remain visible and rank high).

---

## 4. Pre-Approval Request

Please review the proposed plan:
- **Architecture**: In-memory VSM (TF-IDF) + Semantic Concept Expansion in pure Dart. (100% offline, zero latency, highly responsive, zero database migrations required).
- **User Interface**: Pinned glassmorphic search sliver at the top of the main screen, cards dynamically filter and animate "as-you-type".

Ready for your review and approval!
