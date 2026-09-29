import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/app_colors.dart';

class LocationAutocompleteField extends StatefulWidget {
  final String labelText;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final String? userCity;

  const LocationAutocompleteField({
    Key? key,
    required this.labelText,
    required this.controller,
    this.validator,
    this.userCity,
  }) : super(key: key);

  @override
  State<LocationAutocompleteField> createState() =>
      _LocationAutocompleteFieldState();
}

class _LocationAutocompleteFieldState extends State<LocationAutocompleteField> {
  String? _currentQuery;
  String? _lastQuery;
  List<String> _lastOptions = [];
  TextEditingController? _internalController;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onExternalControllerChanged);
  }

  void _onExternalControllerChanged() {
    if (_internalController != null &&
        _internalController!.text != widget.controller.text) {
      _internalController!.text = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalControllerChanged);
    super.dispose();
  }
  // String? _currentQuery;
  // String? _lastQuery;
  // List<String> _lastOptions = [];

  Future<List<String>> _fetchSuggestions(String input) async {
    if (input.isEmpty || input.length < 3) {
      return [];
    }

    if (input == _lastQuery) return _lastOptions;

    _currentQuery = input;
    // Elegant debouncing: Wait 2 seconds (2000ms), then check if the user is still typing the same query
    await Future.delayed(const Duration(milliseconds: 2000));
    if (_currentQuery != input) {
      return []; // The user kept typing, so discard this request
    }

    String query = input;
    // Contextualize the search to the user's city if provided
    if (widget.userCity != null && widget.userCity!.isNotEmpty) {
      if (!query.toLowerCase().contains(widget.userCity!.toLowerCase())) {
        query = '$query, ${widget.userCity}';
      }
    }

    final encodedQuery = Uri.encodeComponent(query);
    // Using Photon (by Komoot), a highly reliable, rate-limit-free OpenStreetMap API
    final String url = 'https://photon.komoot.io/api/?q=$encodedQuery&limit=5';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        final suggestions = features
            .map((feature) {
              final props = feature['properties'];
              final name = props['name'] ?? '';
              final city =
                  props['city'] ?? props['county'] ?? props['district'] ?? '';
              final state = props['state'] ?? '';

              List<String> parts = [];
              if (name.toString().isNotEmpty) parts.add(name.toString());
              if (city.toString().isNotEmpty && city != name)
                parts.add(city.toString());
              if (state.toString().isNotEmpty && state != city)
                parts.add(state.toString());

              return parts.join(', ');
            })
            .where((s) => s.isNotEmpty)
            .toList();

        // Remove duplicates just in case
        final uniqueSuggestions = suggestions.toSet().toList();

        _lastQuery = input;
        _lastOptions = uniqueSuggestions;
        return uniqueSuggestions;
      }
    } catch (e) {
      debugPrint("Error fetching places from Photon: $e");
    }

    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) async {
        return await _fetchSuggestions(textEditingValue.text);
      },
      onSelected: (String selection) {
        widget.controller.text = selection;
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        // Bi-directional sync
        if (_internalController != textEditingController) {
          _internalController = textEditingController;
          _internalController!.addListener(() {
            if (widget.controller.text != _internalController!.text) {
              widget.controller.text = _internalController!.text;
            }
          });
        }

        // Handle pre-filled data
        if (widget.controller.text.isNotEmpty &&
            textEditingController.text.isEmpty) {
          textEditingController.text = widget.controller.text;
        }

        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            suffixIcon:
                const Icon(Icons.location_on, color: AppColors.primary),
          ),
          onFieldSubmitted: (String value) {
            onFieldSubmitted();
          },
          validator: widget.validator,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 250,
                maxWidth: MediaQuery.of(context).size.width -
                    32, // Accommodate horizontal padding
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);

                  final parts = option.split(',');
                  final primaryText =
                      parts.isNotEmpty ? parts.first.trim() : '';
                  final secondaryText =
                      parts.length > 1 ? parts.skip(1).join(',').trim() : '';

                  return InkWell(
                    onTap: () {
                      onSelected(option);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12.0, horizontal: 16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on_outlined,
                              color: Colors.grey, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.black87),
                                children: [
                                  TextSpan(
                                      text: primaryText,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  if (secondaryText.isNotEmpty)
                                    TextSpan(
                                        text: ' $secondaryText',
                                        style: const TextStyle(
                                            color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
