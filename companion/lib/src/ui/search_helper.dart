import 'dart:math' as math;

/// A lightweight, offline-first search engine utilizing a Vector Space Model (VSM)
/// with TF-IDF style weighting and semantic concept expansion.
class SemanticSearchEngine {
  // A pre-compiled set of English stop words to filter out noise.
  static const Set<String> _stopWords = {
    'a', 'about', 'above', 'after', 'again', 'against', 'all', 'am', 'an', 'and',
    'any', 'are', 'arent', 'as', 'at', 'be', 'because', 'been', 'before', 'being',
    'below', 'between', 'both', 'but', 'by', 'cant', 'cannot', 'could', 'couldnt',
    'did', 'didnt', 'do', 'does', 'doesnt', 'doing', 'dont', 'down', 'during',
    'each', 'few', 'for', 'from', 'further', 'had', 'hadnt', 'has', 'hasnt',
    'have', 'havent', 'having', 'he', 'hed', 'hell', 'hes', 'her', 'here',
    'heres', 'hers', 'herself', 'him', 'himself', 'his', 'how', 'hows', 'i',
    'id', 'ill', 'im', 'ive', 'if', 'in', 'into', 'is', 'isnt', 'it', 'its',
    'itself', 'lets', 'me', 'more', 'most', 'mustnt', 'my', 'myself', 'no',
    'nor', 'not', 'of', 'off', 'on', 'once', 'only', 'or', 'other', 'ought',
    'our', 'ours', 'ourselves', 'out', 'over', 'own', 'same', 'shant', 'she',
    'shed', 'shell', 'shes', 'should', 'shouldnt', 'so', 'some', 'such', 'than',
    'that', 'thats', 'the', 'their', 'theirs', 'them', 'themselves', 'then',
    'there', 'theres', 'these', 'they', 'theyd', 'theyll', 'theyre', 'theyve',
    'this', 'those', 'through', 'to', 'too', 'under', 'until', 'up', 'very',
    'was', 'wasnt', 'we', 'wed', 'well', 'were', 'weve', 'werent', 'what',
    'whats', 'when', 'whens', 'where', 'wheres', 'which', 'while', 'who',
    'whos', 'whom', 'why', 'whys', 'with', 'wont', 'would', 'wouldnt', 'you',
    'youd', 'youll', 'youre', 'youve', 'your', 'yours', 'yourself', 'yourselves'
  };

  // Pre-compiled semantic expansion thesaurus mapping general concepts to related terms.
  // When a query term matches a key, the related values are dynamically added to the query vector at reduced weight.
  static const Map<String, List<String>> _semanticThesaurus = {
    'grocery': ['milk', 'food', 'supermarket', 'store', 'buy', 'market', 'apple', 'bread', 'eggs', 'shop', 'groceries'],
    'groceries': ['milk', 'food', 'supermarket', 'store', 'buy', 'market', 'apple', 'bread', 'eggs', 'shop', 'grocery'],
    'shopping': ['milk', 'food', 'supermarket', 'store', 'buy', 'market', 'apple', 'bread', 'eggs', 'shop', 'grocery', 'groceries'],
    'buy': ['shopping', 'store', 'market', 'price', 'purchase', 'shop'],
    'work': ['meeting', 'project', 'boss', 'manager', 'tasks', 'email', 'schedule', 'client', 'job', 'office', 'colleague'],
    'job': ['meeting', 'project', 'boss', 'manager', 'tasks', 'email', 'schedule', 'client', 'work', 'office'],
    'meeting': ['work', 'project', 'schedule', 'calendar', 'zoom', 'call', 'discuss', 'colleague'],
    'task': ['todo', 'list', 'work', 'project', 'action', 'doing'],
    'tasks': ['todo', 'list', 'work', 'project', 'action', 'doing'],
    'todo': ['tasks', 'list', 'action', 'reminder', 'work'],
    'idea': ['inspiration', 'thought', 'concept', 'brainstorming', 'creative', 'design', 'ideas'],
    'ideas': ['inspiration', 'thought', 'concept', 'brainstorming', 'creative', 'design', 'idea'],
    'thought': ['idea', 'concept', 'brainstorming', 'mind', 'inspiration'],
    'thoughts': ['idea', 'concept', 'brainstorming', 'mind', 'inspiration'],
    'personal': ['house', 'family', 'life', 'home', 'health', 'fitness'],
    'home': ['house', 'family', 'personal', 'apartment'],
    'health': ['doctor', 'dentist', 'gym', 'workout', 'fitness', 'medical', 'appointment', 'sick', 'pill', 'medicine'],
    'code': ['developer', 'program', 'coding', 'bug', 'pr', 'git', 'github', 'flutter', 'dart', 'c', 'pebble', 'software', 'programming'],
    'coding': ['developer', 'program', 'code', 'bug', 'pr', 'git', 'github', 'flutter', 'dart', 'c', 'pebble', 'software', 'programming'],
    'programming': ['developer', 'program', 'code', 'bug', 'pr', 'git', 'github', 'flutter', 'dart', 'c', 'pebble', 'software', 'coding'],
    'software': ['developer', 'program', 'code', 'bug', 'pr', 'git', 'github', 'flutter', 'dart', 'c', 'pebble', 'programming', 'coding'],
  };

  /// Tokenizes, normalizes, and filters out common stop words from a raw block of text.
  static List<String> tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Strip punctuation
        .split(RegExp(r'\s+')) // Split by whitespace
        .where((token) => token.isNotEmpty && !_stopWords.contains(token))
        .toList();
  }

  /// Calculates a Cosine Similarity score (0.0 to 1.0) comparing a search query to a note.
  /// 
  /// The note fields are weighted to prioritize matches in the Title over the Body and Transcript:
  /// - Title: weight 2.5
  /// - Body: weight 1.0
  /// - Raw Text Transcript: weight 0.5
  static double computeSimilarity({
    required String query,
    required String title,
    required String body,
    required String rawText,
  }) {
    final queryTokens = tokenize(query);
    if (queryTokens.isEmpty) {
      return 1.0; // Empty query matches everything fully
    }

    // 1. Build Query Vector with Semantic Expansion
    final Map<String, double> queryVector = {};
    for (final token in queryTokens) {
      // Direct exact matches receive a baseline weight of 1.0
      queryVector[token] = (queryVector[token] ?? 0.0) + 1.0;

      // Check for semantic expansions in the thesaurus
      if (_semanticThesaurus.containsKey(token)) {
        for (final expansion in _semanticThesaurus[token]!) {
          // Expanded terms receive a decayed semantic weight of 0.5
          queryVector[expansion] = (queryVector[expansion] ?? 0.0) + 0.5;
        }
      }
    }

    // 2. Build Document Vector with Field Weightings
    final Map<String, double> docVector = {};
    
    final titleTokens = tokenize(title);
    for (final token in titleTokens) {
      docVector[token] = (docVector[token] ?? 0.0) + 2.5;
    }

    final bodyTokens = tokenize(body);
    for (final token in bodyTokens) {
      docVector[token] = (docVector[token] ?? 0.0) + 1.0;
    }

    final rawTokens = tokenize(rawText);
    for (final token in rawTokens) {
      docVector[token] = (docVector[token] ?? 0.0) + 0.5;
    }

    if (docVector.isEmpty) {
      return 0.0;
    }

    // 3. Compute Cosine Similarity
    double dotProduct = 0.0;
    double queryMagnitudeSquared = 0.0;
    double docMagnitudeSquared = 0.0;

    // We calculate magnitudes based on the unique dimensions in both vectors
    queryVector.forEach((key, val) {
      queryMagnitudeSquared += val * val;
      if (docVector.containsKey(key)) {
        dotProduct += val * docVector[key]!;
      }
    });

    docVector.forEach((key, val) {
      docMagnitudeSquared += val * val;
    });

    if (queryMagnitudeSquared == 0.0 || docMagnitudeSquared == 0.0) {
      return 0.0;
    }

    final double queryMagnitude = math.sqrt(queryMagnitudeSquared);
    final double docMagnitude = math.sqrt(docMagnitudeSquared);

    return dotProduct / (queryMagnitude * docMagnitude);
  }
}
